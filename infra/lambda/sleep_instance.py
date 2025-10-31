import os
import datetime
import boto3

EC2 = boto3.client("ec2")
SSM = boto3.client("ssm")

INSTANCE_ID = os.environ["INSTANCE_ID"]
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "5"))
HEARTBEAT_PARAM = os.environ.get("HEARTBEAT_PARAM", "/neon-portfolio/last_heartbeat")
GRACE_MINUTES = int(os.environ.get("GRACE_MINUTES", "10"))

UTC = datetime.timezone.utc


def _now_utc():
    return datetime.datetime.now(UTC)


def _parse_ts(s: str):
    """
    Safely parse ISO8601 timestamps: supports '+00:00' and trailing 'Z'.
    Returns an aware-UTC datetime or None on failure.
    """
    if not s:
        return None
    try:
        # typical form: 2025-10-17T12:34:56.789012+00:00
        dt = datetime.datetime.fromisoformat(s)
    except Exception:
        try:
            # accept 'Z' suffix
            if s.endswith("Z"):
                dt = datetime.datetime.fromisoformat(s[:-1]).replace(tzinfo=UTC)
            else:
                return None
        except Exception:
            return None
    # if naive — assume UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def handler(event, context):
    # 1) Instance state
    try:
        r = EC2.describe_instances(InstanceIds=[INSTANCE_ID])
        inst = r["Reservations"][0]["Instances"][0]
        state = inst["State"]["Name"]
        launch = inst.get("LaunchTime")  # aware-UTC
        tags = {t.get("Key"): t.get("Value") for t in inst.get("Tags", [])}
    except Exception as e:
        print(f"[sleep] describe_failed: {e}")
        return {"ok": False, "error": f"describe_failed: {e}"}

    # 2) Manual override via tag
    v = str(tags.get("Autostop", "")).strip().lower()
    if v in ("off", "no", "false", "0", "disable", "disabled", "never", "stop-off"):
        print("[sleep] override: Autostop=off → noop")
        return {"ok": True, "action": "noop", "reason": "tag Autostop=off"}

    # 3) Only for running state
    if state != "running":
        print(f"[sleep] state={state} → noop")
        return {"ok": True, "action": "noop", "reason": f"state={state}"}

    # 4) Launch grace period
    if launch:
        alive_min = (_now_utc() - launch).total_seconds() / 60.0
        if alive_min < GRACE_MINUTES:
            print(f"[sleep] grace: alive={alive_min:.1f}m < {GRACE_MINUTES}m → noop")
            return {"ok": True, "action": "noop", "reason": f"grace {alive_min:.1f}m < {GRACE_MINUTES}m"}

    # 5) Last heartbeat from SSM
    try:
        val = SSM.get_parameter(Name=HEARTBEAT_PARAM)["Parameter"]["Value"]
        last = _parse_ts(val)
    except Exception as e:
        print(f"[sleep] get_parameter failed: {e}")
        last = None

    if last is None:
        # if there has never been a heartbeat — do not stop yet (first deploy/boot)
        print("[sleep] no-heartbeat-yet → noop")
        return {"ok": True, "action": "noop", "reason": "no-heartbeat-yet"}

    now = _now_utc()
    # guard against future timestamps due to clock drift
    if last > now:
        print(f"[sleep] heartbeat in the future (last={last.isoformat()}) → noop")
        return {"ok": True, "action": "noop", "reason": "heartbeat-in-future"}

    idle = (now - last).total_seconds() / 60.0
    if idle < IDLE_MINUTES:
        print(f"[sleep] idle {idle:.1f}m < {IDLE_MINUTES}m → noop")
        return {"ok": True, "action": "noop", "reason": f"idle {idle:.1f}m < {IDLE_MINUTES}m"}

    # 6) Stop the instance
    try:
        EC2.stop_instances(InstanceIds=[INSTANCE_ID])
        print(f"[sleep] stop_instances: idle_min={idle:.2f}")
        return {"ok": True, "action": "stop", "idle_min": round(idle, 2)}
    except Exception as e:
        print(f"[sleep] stop_failed: {e}")
        return {"ok": False, "error": f"stop_failed: {e}"}