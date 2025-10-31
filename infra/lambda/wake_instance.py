import json
import os
import datetime
import time
import urllib.request
from urllib.error import HTTPError  # treat 4xx as "port is answering" (reachable)
import boto3
from zoneinfo import ZoneInfo

# --- AWS clients ---
EC2 = boto3.client("ec2")
SSM = boto3.client("ssm")

# --- Environment ---
INSTANCE_ID = os.environ["INSTANCE_ID"]
TARGET_URL = os.environ.get("TARGET_URL", "")
HEALTH_URL = os.environ.get("HEALTH_URL", "")
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "5"))
HEARTBEAT_KEY = os.environ.get("HEARTBEAT_PARAM", "/neon-portfolio/last_heartbeat")
NODE_PORT = int(os.environ.get("NODE_PORT", "30080"))
LOCAL_TZ_NAME = os.environ.get("LOCAL_TZ", "America/Chicago")

# Region and kubeconfig settings
REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
KUBECONFIG_PARAM = os.environ.get("KUBECONFIG_PARAM", "/helmkube/k3s/kubeconfig")

# Optionally refresh ECR pull secret and restart deployment on wake
REFRESH_ECR_ON_WAKE = os.environ.get("REFRESH_ECR_ON_WAKE", "false").lower() in ("1", "true", "yes")

# Auto-update kubeconfig on wake (enabled by default)
AUTO_UPDATE_KUBECONFIG = os.environ.get("AUTO_UPDATE_KUBECONFIG", "true").lower() in ("1", "true", "yes")

# Timeouts / pacing
HC_TIMEOUT_S = float(os.environ.get("HEALTHCHECK_TIMEOUT_SEC", "3.5"))
DNS_WAIT_TOTAL_SEC = int(os.environ.get("DNS_WAIT_TOTAL_SEC", "60"))
# Do not block root ("/"): the UI polls /status by itself
READY_POLL_TOTAL_SEC = 0  # enforce zero so we never block at "/"
READY_POLL_INTERVAL_SEC = float(os.environ.get("READY_POLL_INTERVAL_SEC", "3.0"))

# ---------------- Helpers ----------------

def _now_utc():
    return datetime.datetime.now(datetime.timezone.utc)

def _now_local():
    # Return current time in the configured local timezone; fall back to system time if unknown
    try:
        return datetime.datetime.now(ZoneInfo(LOCAL_TZ_NAME))
    except Exception:
        return datetime.datetime.now()

def _eta_text(minutes=2):
    # Human-readable ETA shown on the waiting page
    return (_now_local() + datetime.timedelta(minutes=minutes)).strftime("%H:%M")

def _build_url(host: str, port: int, path: str = "/") -> str:
    # Compose http://host:port/path with graceful fallback to env URLs
    if not host:
        return TARGET_URL or HEALTH_URL or "/"
    if not path.startswith("/"):
        path = "/" + path
    url = f"http://{host}:{port}{path}"
    if path == "/" and not url.endswith("/"):
        url += "/"
    return url

def _describe_all():
    """Return (state, PublicDnsName, PublicIpAddress). Public IP typically appears sooner than DNS."""
    r = EC2.describe_instances(InstanceIds=[INSTANCE_ID])
    inst = r["Reservations"][0]["Instances"][0]
    state = inst["State"]["Name"]
    dns = inst.get("PublicDnsName") or ""
    ip = inst.get("PublicIpAddress") or ""
    return state, dns, ip

def _build_target(dns: str | None, ip: str | None) -> str:
    # Prefer IP (available earlier), then DNS, then environment fallbacks
    if ip:
        return _build_url(ip, NODE_PORT, "/")
    if dns:
        return _build_url(dns, NODE_PORT, "/")
    return TARGET_URL or HEALTH_URL or "/"

def _probe(url: str, timeout: float, method: str) -> bool:
    # Low-level HTTP probe: 2xx–4xx = "reachable" (port answers something)
    try:
        req = urllib.request.Request(url, method=method, headers={"User-Agent": "wake-check"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return 200 <= r.status < 500
    except HTTPError as e:
        return 200 <= e.code < 500
    except Exception:
        return False

def _get_public_http_ok(url: str, timeout: float) -> bool:
    # Try HEAD first, then GET
    return _probe(url, timeout, "HEAD") or _probe(url, timeout, "GET")

def _start_instance():
    """Idempotently attempt to start the instance; ignore IncorrectInstanceState if already starting/running."""
    try:
        EC2.start_instances(InstanceIds=[INSTANCE_ID])
    except Exception as e:
        if "IncorrectInstanceState" not in str(e):
            raise

def _wait_for_dns(max_wait_s: int = DNS_WAIT_TOTAL_SEC) -> str:
    """Soft wait for PublicDnsName (we still use IP immediately when available)."""
    deadline = time.time() + max_wait_s
    dns = ""
    while time.time() < deadline:
        try:
            _, dns, _ = _describe_all()
            if dns:
                return dns
        except Exception:
            pass
        time.sleep(2)
    return dns

def _put_heartbeat(ts=None):
    # Store a UTC heartbeat timestamp in SSM Parameter Store
    if ts is None:
        ts = _now_utc().isoformat()
    SSM.put_parameter(Name=HEARTBEAT_KEY, Value=ts, Type="String", Overwrite=True)

def _resp(status=200, body="", html=False, headers=None):
    # API Gateway-compatible response wrapper
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
    # Waiting page HTML. JS polls /status and redirects when ready.
    html = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Cache-Control" content="no-store, max-age=0"/>
<meta http-equiv="Pragma" content="no-cache"/>
<meta http-equiv="Expires" content="0"/>
<title>Waking up your server…</title>
<style>
  :root { --bg:#070910; --fg:#E6E8EC; --muted:#AAB1BC; --stroke:rgba(255,255,255,0.12);
          --glass1:rgba(255,255,255,.06); --glass2:rgba(255,255,255,.03);
          --a1:#6cf; --a2:#9f6; --a3:#f69; }
  html,body { height:100%; margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif; }
  .wrap { min-height:100%; display:flex; align-items:center; justify-content:center; padding:32px; }
  .card { width:min(720px,100%); border:1px solid var(--stroke);
          background:linear-gradient(180deg, var(--glass1), var(--glass2));
          border-radius:16px; padding:24px; box-shadow:0 20px 60px rgba(0,0,0,.45), inset 0 0 0 1px rgba(255,255,255,.04); }
  .title { font-weight:800; font-size:22px; display:flex; gap:10px; align-items:center }
  .pulse { width:10px; height:10px; border-radius:50%; background:radial-gradient(circle at 50% 50%, var(--a1) 0 55%, transparent 56%); box-shadow:0 0 12px var(--a1), 0 0 24px rgba(102,204,255,.5); animation:blink 1.25s ease-in-out infinite; }
  @keyframes blink { 50% { filter:brightness(1.6) } }
  .bar { margin:16px 0 10px; height:10px; background:rgba(255,255,255,.08); border:1px solid var(--stroke); border-radius:999px; overflow:hidden }
  .bar > i { display:block; height:100%; width:0; background:linear-gradient(90deg, var(--a1), var(--a2), var(--a3), var(--a1)); background-size:200% 100%; animation:flow 3.2s linear infinite; }
  @keyframes flow { to { background-position:200% 0 } }
  .row { display:flex; gap:12px; align-items:center; justify-content:space-between; flex-wrap:wrap; }
  .caps { text-transform:uppercase; letter-spacing:.12em; font-size:12px; color:var(--muted) }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size:13px; }
  .btns { display:flex; gap:10px; flex-wrap:wrap; margin-top:14px }
  .btn { border:1px solid var(--stroke); background:rgba(255,255,255,.06); color:var(--fg); padding:10px 14px; border-radius:10px; cursor:pointer; font-weight:600; }
  .btn-primary { border-color:transparent; background:linear-gradient(90deg, var(--a1), var(--a3)); }
  .small { color:var(--muted); font-size:12px }
</style>
<body>
  <div class="wrap">
    <div class="card" role="status" aria-live="polite">
      <div class="title"><span class="pulse" aria-hidden="true"></span> Waking up your server…</div>
      <div class="sub">Estimated time: ~2–3 minutes (by __ETA__). You can keep this tab open.</div>
      <div class="bar" aria-hidden="true"><i id="progress"></i></div>

      <div class="row">
        <div><div class="caps">Live timer</div><div class="mono"><span id="elapsed">00:00</span> elapsed</div></div>
        <div><div class="caps">Current state</div><div class="mono" id="state">checking…</div></div>
        <div><div class="caps">Auto-redirect</div><div class="mono">only when ready</div></div>
      </div>

      <p class="mono" id="hint">We will redirect as soon as the app port is reachable.</p>

      <div class="btns">
        <button class="btn btn-primary" id="openNow">Open site now</button>
        <button class="btn" id="refresh">Refresh status</button>
      </div>

      <div style="margin-top:10px; text-align:right" class="small">Auto-redirect triggers only when the app is <b>ready</b>.</div>
    </div>
  </div>

<script>
let TARGET = "__TARGET__";
const STATUS_URL = location.origin.replace(/\/$/, "") + "/status";

// progress bar
const progressEl = document.getElementById("progress");
let pct = 0;
setInterval(() => { pct = Math.min(100, pct + 2); progressEl.style.width = pct + "%"; }, 700);

// elapsed
const elapsedEl = document.getElementById("elapsed");
const startTs = Date.now();
setInterval(() => {
  const d = Date.now() - startTs;
  const mm = String(Math.floor(d/60000)).padStart(2,"0");
  const ss = String(Math.floor((d%60000)/1000)).padStart(2,"0");
  elapsedEl.textContent = `${mm}:${ss}`;
}, 250);

// send heartbeat every 40s so the instance doesn't fall asleep while waiting
setInterval(() => { fetch("/heartbeat", { method: "POST", cache: "no-store" }).catch(()=>{}); }, 40000);

const stateEl = document.getElementById("state");
const hintEl  = document.getElementById("hint");
document.getElementById("openNow").onclick = () => { window.location.href = TARGET; };
document.getElementById("refresh").onclick = () => { poll(true); };

async function poll(force) {
  try {
    const r = await fetch(STATUS_URL + (force ? `?t=${Date.now()}` : ""), { cache:"no-store" });
    const j = await r.json();

    if (j.target && typeof j.target === "string") TARGET = j.target;
    stateEl.textContent = j.state || "unknown";

    if (j.ready === true) { window.location.href = TARGET; return; }

    if (j.state === "pending")      hintEl.textContent = "Instance is starting… waiting for the app port to open.";
    else if (j.state === "running") hintEl.textContent = "Server is up. Waiting for the app port to be reachable…";
    else if (j.state === "stopped") hintEl.textContent = "Starting the instance…";
    else if (j.state === "stopping")hintEl.textContent = "Instance is stopping… attempting to start it.";
    else                            hintEl.textContent = "Waiting…";
  } catch (e) {
    stateEl.textContent = "status unreachable";
    hintEl.textContent  = "Status endpoint is not reachable. You can still try 'Open site now'.";
  } finally {
    setTimeout(poll, 3000);
  }
}
poll(true); // first request immediately
</script>
</body>
</html>"""
    return html.replace("__ETA__", eta_text).replace("__TARGET__", target_now)

# ---------------- Wake-time helpers ----------------

def _refresh_ecr_secret_and_restart():
    """
    Optionally refresh ECR Docker secret on the node via SSM RunCommand
    and restart the deployment. Enabled only if REFRESH_ECR_ON_WAKE=true.
    Failures are non-fatal.
    """
    if not REFRESH_ECR_ON_WAKE:
        return
    try:
        commands = [
            "set -euo pipefail",
            f"REGION='{REGION}'",
            "export AWS_DEFAULT_REGION=\"$REGION\"",
            "K='kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml'",
            # resolve account ECR registry
            "ACCNT=\"$(aws sts get-caller-identity --query 'Account' --output text)\"",
            "ECR_REG=\"${ACCNT}.dkr.ecr.${REGION}.amazonaws.com\"",
            "ECR_PASS=\"$(aws ecr get-login-password --region \"$REGION\")\"",
            "$K -n default delete secret ecr-dockercfg --ignore-not-found",
            "$K -n default create secret docker-registry ecr-dockercfg --docker-server=\"$ECR_REG\" --docker-username=AWS --docker-password=\"$ECR_PASS\" --docker-email=none@none",
            "$K -n default patch serviceaccount default --type merge -p '{\"imagePullSecrets\":[{\"name\":\"ecr-dockercfg\"}]}'",
            "$K -n default rollout restart deploy/hello || true",
        ]
        SSM.send_command(
            InstanceIds=[INSTANCE_ID],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": commands},
            CloudWatchOutputConfig={
                "CloudWatchLogGroupName": "/ssm/refresh-ecr",
                "CloudWatchOutputEnabled": True,
            },
        )
    except Exception:
        # keep response intact even if SSM fails
        pass

def _update_kubeconfig_via_ssm():
    """
    Non-blocking: read k3s.yaml on the node, replace 'server' host with
    current public DNS/IP, and store it to SSM (SecureString).
    Requires the EC2 role to allow ssm:PutParameter.
    """
    if not AUTO_UPDATE_KUBECONFIG:
        return
    try:
        commands = [
            "set -euo pipefail",
            f"REGION='{REGION}'",
            f"KCFG='{KUBECONFIG_PARAM}'",
            "export AWS_DEFAULT_REGION=\"$REGION\"",
            # IMDSv2 token + public DNS/IP
            "TOKEN=$(curl -fsX PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')",
            "HOST=$(curl -fsH \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/public-hostname || curl -fsH \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/public-ipv4 || true)",
            "CONTENT=\"$(cat /etc/rancher/k3s/k3s.yaml)\"",
            # replace any host part in server: https://<host>:6443
            "if [ -n \"$HOST\" ]; then CONTENT=$(printf '%s' \"$CONTENT\" | sed -E \"s#(server:[[:space:]]*https?://)[^:]+:6443#\\1${HOST}:6443#\"); fi",
            "echo \"$CONTENT\" | grep -q '^apiVersion:'",
            "tf=$(mktemp); printf '%s\n' \"$CONTENT\" > \"$tf\"",
            "aws ssm put-parameter --name \"$KCFG\" --type SecureString --value \"$(cat \"$tf\")\" --overwrite >/dev/null 2>&1 || true",
            "rm -f \"$tf\"",
        ]
        SSM.send_command(
            InstanceIds=[INSTANCE_ID],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": commands},
            CloudWatchOutputConfig={
                "CloudWatchLogGroupName": "/ssm/refresh-kubeconfig",
                "CloudWatchOutputEnabled": True,
            },
        )
    except Exception:
        # do not affect main response
        pass

# ---------------- Lambda handler ----------------

def handler(event, context):
    try:
        # Normalize HTTP API v2 path & method
        http_ctx = event.get("requestContext", {}).get("http", {}) or {}
        raw_path = http_ctx.get("path") or event.get("rawPath") or event.get("path") or "/"
        path_norm = (raw_path.split("?")[0] or "/").rstrip("/") or "/"
        method = http_ctx.get("method", "GET")

        def _is(p: str) -> bool:
            return (path_norm or "/") == (p.rstrip("/") or "/")

        # /heartbeat — record timestamp
        if _is("/heartbeat") and method in ("GET", "POST"):
            _put_heartbeat()
            return _resp(200, {"ok": True, "ts": _now_utc().isoformat()})

        # /status — quick check via IP/DNS (or HEALTH_URL)
        if _is("/status"):
            try:
                state, dns, ip = _describe_all()
            except Exception as e:
                return _resp(200, {"ok": False, "error": str(e), "state": "unknown"})

            target_now = _build_target(dns, ip)
            http_ok = False
            if state == "running":
                candidates = []
                if HEALTH_URL:
                    candidates.append(HEALTH_URL)
                if ip:
                    candidates.append(_build_url(ip, NODE_PORT, "/"))
                if dns:
                    candidates.append(_build_url(dns, NODE_PORT, "/"))
                for url in candidates:
                    if _get_public_http_ok(url, timeout=HC_TIMEOUT_S):
                        http_ok = True
                        target_now = url
                        break
            return _resp(200, {"ok": True, "ready": bool(http_ok), "state": state, "target": target_now})

        # "/" — return the waiting page immediately, nudge wake-up side effects without blocking
        try:
            _start_instance()
            _put_heartbeat()
            _update_kubeconfig_via_ssm()
            _refresh_ecr_secret_and_restart()
        except Exception:
            # never block the user even if side effects fail
            pass

        # Build target URL (env → best effort from describe)
        target_now = TARGET_URL or HEALTH_URL or "/"
        try:
            state2, dns2, ip2 = _describe_all()
            target_now = _build_target(dns2, ip2) or target_now
        except Exception:
            pass

        # Do not wait here — the front-end polls /status and redirects when ready
        eta = _eta_text(2)
        return _resp(200, _html_wait(eta, target_now), html=True)

    except Exception as e:
        return _resp(200, {"ok": False, "fatal": str(e)})