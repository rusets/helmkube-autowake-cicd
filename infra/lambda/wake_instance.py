import json
import os
import datetime
import urllib.request
import boto3
from zoneinfo import ZoneInfo  # local time zone support

# --- AWS clients ---
EC2 = boto3.client("ec2")
SSM = boto3.client("ssm")

# --- Environment ---
# e.g. i-xxxxxxxx
INSTANCE_ID = os.environ["INSTANCE_ID"]
# optional fallback
TARGET_URL = os.environ.get("TARGET_URL", "")
# optional fallback
HEALTH_URL = os.environ.get("HEALTH_URL", "")
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "5"))
HEARTBEAT_KEY = os.environ.get(
    "HEARTBEAT_PARAM", "/neon-portfolio/last_heartbeat")
NODE_PORT = int(os.environ.get("NODE_PORT", "30080"))
LOCAL_TZ_NAME = os.environ.get(
    "LOCAL_TZ", "America/Chicago")     # local time zone for ETA

# ---------------- Helpers ----------------


def _now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def _now_local():
    try:
        return datetime.datetime.now(ZoneInfo(LOCAL_TZ_NAME))
    except Exception:
        return datetime.datetime.now()


def _eta_text(minutes=2):
    return (_now_local() + datetime.timedelta(minutes=minutes)).strftime("%H:%M")


def _build_url(host: str, port: int, path: str = "/") -> str:
    """Build http://host:port/path ensuring trailing slash for root."""
    if not host:
        return TARGET_URL or HEALTH_URL or "/"
    path = path or "/"
    if not path.startswith("/"):
        path = "/" + path
    url = f"http://{host}:{port}{path}"
    if path == "/" and not url.endswith("/"):
        url += "/"
    return url


def _get_public_dns() -> str:
    """Fetch current EC2 PublicDnsName each time (handles instance changes)."""
    r = EC2.describe_instances(InstanceIds=[INSTANCE_ID])
    return r["Reservations"][0]["Instances"][0].get("PublicDnsName") or ""


def _current_target_url() -> str:
    live = _get_public_dns()
    return _build_url(live, NODE_PORT, "/") if live else (TARGET_URL or HEALTH_URL or "/")


def _current_health_url() -> str:
    live = _get_public_dns()
    return _build_url(live, NODE_PORT, "/") if live else (HEALTH_URL or TARGET_URL or "/")


def _get_public_http_ok(url, timeout=4.0):
    """Try HEAD first, then GET. Treat 2xx–4xx as reachable (port is up)."""
    try:
        req = urllib.request.Request(url, method="HEAD", headers={
                                     "User-Agent": "wake-check"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return 200 <= r.status < 500
    except Exception:
        pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "wake-check"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return 200 <= r.status < 500
    except Exception:
        return False


def _get_instance_state():
    r = EC2.describe_instances(InstanceIds=[INSTANCE_ID])
    return r["Reservations"][0]["Instances"][0]["State"]["Name"]


def _start_instance():
    """Start EC2; ignore IncorrectInstanceState when already starting/running."""
    try:
        EC2.start_instances(InstanceIds=[INSTANCE_ID])
    except Exception as e:
        if "IncorrectInstanceState" not in str(e):
            raise


def _put_heartbeat(ts=None):
    """Write/update last heartbeat timestamp into SSM Parameter Store."""
    if ts is None:
        ts = _now_utc().isoformat()
    SSM.put_parameter(Name=HEARTBEAT_KEY, Value=ts,
                      Type="String", Overwrite=True)


def _resp(status=200, body="", html=False, headers=None):
    """Unified API Gateway response. Never throws (returns JSON/HTML)."""
    h = {
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-store, max-age=0",
        "Pragma": "no-cache",
        "Expires": "0",
        "X-Robots-Tag": "noindex, nofollow",
    }
    if html:
        h["Content-Type"] = "text/html; charset=utf-8"
        b = body
    else:
        h["Content-Type"] = "application/json"
        b = json.dumps(body)
    if headers:
        h.update(headers)
    return {"statusCode": status, "headers": h, "body": b}


def _html_wait(eta_text, target_now):
    """
    Waiting page (no 'Report issue', no target line).
    RGB neon bubbles background; client redirects only when j.ready === true.
    """
    html = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Cache-Control" content="no-store, max-age=0"/>
<meta http-equiv="Pragma" content="no-cache"/>
<meta http-equiv="Expires" content="0"/>
<title>Waking up your server…</title>
<style>
  :root {
    --bg:#070910;
    --fg:#E6E8EC;
    --muted:#AAB1BC;
    --stroke:rgba(255,255,255,0.12);
    --glass1:rgba(255,255,255,.06);
    --glass2:rgba(255,255,255,.03);
    --a1:#6cf; --a2:#9f6; --a3:#f69;
  }
  html,body { height:100%; margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 Inter,system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif; }

  .wrap { position:relative; min-height:100%; display:flex; align-items:center; justify-content:center; padding:32px; overflow:hidden; }
  .layer { position:absolute; inset:-10%; filter:saturate(1.25) contrast(1.05); }
  .layer.l1 { z-index:0; filter:blur(26px) saturate(1.2); opacity:.9;
    background:
      radial-gradient(140px 140px at 18% 22%, rgba(102,204,255,.26), transparent 65%),
      radial-gradient(160px 160px at 82% 30%, rgba(159,255,102,.22), transparent 62%),
      radial-gradient(140px 140px at 26% 78%, rgba(255,102,153,.24), transparent 64%),
      radial-gradient(120px 120px at 70% 72%, rgba(102,204,255,.20), transparent 66%);
    animation: float1 14s ease-in-out infinite alternate;
  }
  .layer.l2 { z-index:1; mix-blend-mode:screen; filter:blur(14px) saturate(1.35); opacity:.85;
    background:
      radial-gradient(110px 110px at 32% 28%, rgba(159,255,102,.24), transparent 62%),
      radial-gradient(130px 130px at 74% 18%, rgba(255,102,153,.26), transparent 60%),
      radial-gradient(100px 100px at 58% 86%, rgba(102,204,255,.22), transparent 60%);
    animation: float2 18s ease-in-out infinite alternate;
  }
  .layer.l3 { z-index:2; pointer-events:none; opacity:.55;
    background:
      radial-gradient(60px 60px at 20% 60%, rgba(108,207,255,.0) 58%, rgba(108,207,255,.85) 60%, rgba(108,207,255,.0) 64%),
      radial-gradient(72px 72px at 78% 44%, rgba(159,255,102,.0) 57%, rgba(159,255,102,.85) 59%, rgba(159,255,102,.0) 64%),
      radial-gradient(56px 56px at 42% 24%, rgba(255,102,153,.0) 58%, rgba(255,102,153,.85) 60%, rgba(255,102,153,.0) 65%);
    filter: blur(0.4px) drop-shadow(0 0 8px rgba(108,207,255,.55));
    animation: float3 22s ease-in-out infinite alternate;
  }
  @keyframes float1 { 0% { transform:translateY(0) } 100% { transform:translateY(-22px) } }
  @keyframes float2 { 0% { transform:translate(0,0) } 100% { transform:translate(-14px,16px) } }
  @keyframes float3 { 0% { transform:translate(0,0) } 100% { transform:translate(10px,-14px) } }

  .card {
    position:relative; z-index:3; width:min(720px,100%); border:1px solid var(--stroke);
    background:linear-gradient(180deg, var(--glass1), var(--glass2));
    border-radius:16px; padding:24px 24px 18px;
    box-shadow:0 20px 60px rgba(0,0,0,.45), inset 0 0 0 1px rgba(255,255,255,.04);
    backdrop-filter:saturate(1.1) blur(6px);
  }
  .title { font-weight:800; font-size:22px; display:flex; align-items:center; gap:10px; }
  .title .pulse {
    width:10px; height:10px; border-radius:50%;
    background:radial-gradient(circle at 50% 50%, var(--a1) 0 55%, transparent 56%);
    box-shadow:0 0 12px var(--a1), 0 0 24px rgba(102,204,255,.5);
    animation:blink 1.25s ease-in-out infinite;
  }
  @keyframes blink { 50% { filter:brightness(1.6) } }

  .sub { color:var(--muted); margin-top:4px; font-size:14px }
  .bar { margin:16px 0 10px; height:10px; background:rgba(255,255,255,.08); border:1px solid var(--stroke); border-radius:999px; overflow:hidden }
  .bar > i { display:block; height:100%; width:0; background:linear-gradient(90deg, var(--a1), var(--a2), var(--a3), var(--a1)); background-size:200% 100%; animation:flow 3.2s linear infinite; }
  @keyframes flow { to { background-position:200% 0 } }

  .row { display:flex; gap:12px; align-items:center; justify-content:space-between; flex-wrap:wrap; }
  .caps { text-transform:uppercase; letter-spacing:.12em; font-size:12px; color:var(--muted) }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size:13px; }
  .hint { color:var(--muted); font-size:13px; margin-top:8px }
  .btns { display:flex; gap:10px; flex-wrap:wrap; margin-top:14px }
  .btn {
    appearance:none; border:1px solid var(--stroke); background:rgba(255,255,255,.06); color:var(--fg);
    padding:10px 14px; border-radius:10px; cursor:pointer; font-weight:600;
    transition:transform .06s ease, background .2s ease, border-color .2s ease;
  }
  .btn:hover { transform:translateY(-1px); background:rgba(255,255,255,.10); border-color:rgba(255,255,255,.18) }
  .btn-primary { border-color:transparent; background:linear-gradient(90deg, var(--a1), var(--a3)); }

  .foot { display:flex; align-items:center; justify-content:flex-end; margin-top:10px; gap:10px; flex-wrap:wrap }
  .small { color:var(--muted); font-size:12px }
</style>

<body>
  <div class="wrap">
    <div class="layer l1" aria-hidden="true"></div>
    <div class="layer l2" aria-hidden="true"></div>
    <div class="layer l3" aria-hidden="true"></div>

    <div class="card" role="status" aria-live="polite">
      <div class="title">
        <span class="pulse" aria-hidden="true"></span>
        Waking up your server…
      </div>
      <div class="sub">Estimated time: ~2–3 minutes (by __ETA__). You can keep this tab open.</div>

      <div class="bar" aria-hidden="true"><i id="progress"></i></div>

      <div class="row">
        <div>
          <div class="caps">Live timer</div>
          <div class="mono"><span id="elapsed">00:00</span> elapsed</div>
        </div>
        <div>
          <div class="caps">Current state</div>
          <div class="mono" id="state">checking…</div>
        </div>
        <div>
          <div class="caps">Auto-redirect</div>
          <div class="mono"><span id="hardEta">03:00</span> max</div>
        </div>
      </div>

      <p class="hint" id="hint">We will redirect as soon as the app port is reachable.</p>

      <div class="btns">
        <button class="btn btn-primary" id="openNow">Open site now</button>
        <button class="btn" id="refresh">Refresh status</button>
      </div>

      <div class="foot">
        <div class="small">Auto-redirect triggers only when the app is <b>ready</b>.</div>
      </div>
    </div>
  </div>

<script>
let TARGET = "__TARGET__";
const STATUS_URL = location.origin.replace(/\/$/, "") + "/status";

// progress bar
const progressEl = document.getElementById("progress");
let pct = 0;
setInterval(() => { pct = Math.min(100, pct + 2); progressEl.style.width = pct + "%"; }, 700);

// elapsed + hard fallback
const elapsedEl = document.getElementById("elapsed");
const hardEtaEl = document.getElementById("hardEta");
const startTs = Date.now();
const HARD_LIMIT_MS = 180000; // 3 minutes fallback
setInterval(() => {
  const d = Date.now() - startTs;
  const mm = String(Math.floor(d/60000)).padStart(2,"0");
  const ss = String(Math.floor((d%60000)/1000)).padStart(2,"0");
  elapsedEl.textContent = `${mm}:${ss}`;
  const remain = Math.max(0, HARD_LIMIT_MS - d);
  const rmm = String(Math.floor(remain/60000)).padStart(2,"0");
  const rss = String(Math.floor((remain%60000)/1000)).padStart(2,"0");
  hardEtaEl.textContent = `${rmm}:${rss}`;
}, 250);

// state/hints
const stateEl = document.getElementById("state");
const hintEl  = document.getElementById("hint");

document.getElementById("openNow").onclick = () => window.location.href = TARGET;
document.getElementById("refresh").onclick = () => poll(true);

// hard fallback (user may still open even if app not ready)
setTimeout(() => window.location.href = TARGET, HARD_LIMIT_MS);

async function poll(force) {
  try {
    const r = await fetch(STATUS_URL + (force ? `?t=${Date.now()}` : ""), { cache:"no-store" });
    const j = await r.json();

    // Always take live target from API (handles EC2 replacement)
    if (j.target && typeof j.target === "string") {
      TARGET = j.target;
    }

    stateEl.textContent = j.state || "unknown";

    // REDIRECT ONLY WHEN PORT IS READY
    if (j.ready === true) {
      window.location.href = TARGET;
      return;
    }

    if (j.state === "pending") {
      hintEl.textContent = "Instance is starting… waiting for the app port to open.";
    } else if (j.state === "running") {
      hintEl.textContent = "Server is up. Waiting for the app port to be reachable…";
    } else if (j.state === "stopped") {
      hintEl.textContent = "Starting the instance…";
    } else {
      hintEl.textContent = "Waiting…";
    }
  } catch (e) {
    stateEl.textContent = "status unreachable";
    hintEl.textContent  = "Status endpoint is not reachable. You can still try 'Open site now'.";
  } finally {
    setTimeout(poll, 3000);
  }
}
poll();
</script>
</body>
</html>"""
    return html.replace("__ETA__", eta_text).replace("__TARGET__", target_now)

# ---------------- Lambda handler (safe) ----------------


def handler(event, context):
    """Never raise to API Gateway; return JSON/HTML with details instead."""
    try:
        raw_path = event.get("rawPath") or event.get("path") or "/"
        method = event.get("requestContext", {}).get(
            "http", {}).get("method", "GET")

        # heartbeat to prevent idle sleep
        if raw_path.startswith("/heartbeat") and method in ("GET", "POST"):
            _put_heartbeat()
            return _resp(200, {"ok": True, "ts": _now_utc().isoformat()})

        # status: report EC2 state, port readiness, and live target URL
        if raw_path.startswith("/status"):
            try:
                state = _get_instance_state()
            except Exception as e:
                return _resp(200, {"ok": False, "error": str(e), "state": "unknown"})

            target_now = _current_target_url()

            http_ok = False
            if state == "running":
                try:
                    http_ok = _get_public_http_ok(
                        _current_health_url(), timeout=3.5)
                except Exception as e:
                    return _resp(200, {"ok": False, "error": str(e), "state": state, "ready": False, "target": target_now})

            return _resp(200, {"ok": True, "ready": bool(http_ok), "state": state, "target": target_now})

        # root: start if needed; otherwise show waiting page until port ready
        try:
            state = _get_instance_state()
        except Exception as e:
            return _resp(200, {"ok": False, "error": str(e)}, html=False)

        target_now = _current_target_url()

        if state == "stopped":
            _start_instance()
            _put_heartbeat()

        http_ok = False
        if state in ("pending", "running"):
            try:
                http_ok = _get_public_http_ok(
                    _current_health_url(), timeout=3.5)
            except Exception:
                http_ok = False

        if http_ok:
            return _resp(302, {}, headers={"Location": target_now})

        eta = _eta_text(2)
        return _resp(200, _html_wait(eta, target_now), html=True)

    except Exception as e:
        return _resp(200, {"ok": False, "fatal": str(e)})
