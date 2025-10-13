import os
import datetime
import boto3

EC2 = boto3.client("ec2")
SSM = boto3.client("ssm")

INSTANCE_ID = os.environ["INSTANCE_ID"]
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "5"))
HEARTBEAT_PARAM = os.environ.get(
    "HEARTBEAT_PARAM", "/neon-portfolio/last_heartbeat")
GRACE_MINUTES = int(os.environ.get("GRACE_MINUTES", "10")
                    )  # grace after boot (minutes)


def _now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def handler(event, context):
    # Describe instance
    try:
        r = EC2.describe_instances(InstanceIds=[INSTANCE_ID])
        inst = r["Reservations"][0]["Instances"][0]
        state = inst["State"]["Name"]
        launch = inst.get("LaunchTime")
        tags = {t.get("Key"): t.get("Value") for t in inst.get("Tags", [])}
    except Exception as e:
        return {"ok": False, "error": f"describe_failed: {e}"}

    # Manual override via tag
    v = str(tags.get("Autostop", "")).lower()
    if v in ("off", "no", "false", "0", "disable", "disabled"):
        return {"ok": True, "action": "noop", "reason": "tag Autostop=off"}

    # Only act on running
    if state != "running":
        return {"ok": True, "action": "noop", "reason": f"state={state}"}

    # Grace period after boot
    if launch:
        alive = (_now_utc() - launch).total_seconds() / 60.0
        if alive < GRACE_MINUTES:
            return {"ok": True, "action": "noop", "reason": f"grace {alive:.1f}m < {GRACE_MINUTES}m"}

    # Last heartbeat
    try:
        val = SSM.get_parameter(Name=HEARTBEAT_PARAM)["Parameter"]["Value"]
        last = datetime.datetime.fromisoformat(val)
    except Exception:
        last = None

    if last is None:
        return {"ok": True, "action": "noop", "reason": "no-heartbeat-yet"}

    idle = (_now_utc() - last).total_seconds() / 60.0
    if idle < IDLE_MINUTES:
        return {"ok": True, "action": "noop", "reason": f"idle {idle:.1f}m < {IDLE_MINUTES}m"}

    # Stop instance
    try:
        EC2.stop_instances(InstanceIds=[INSTANCE_ID])
        return {"ok": True, "action": "stop", "idle_min": round(idle, 2)}
    except Exception as e:
        return {"ok": False, "error": f"stop_failed: {e}"}
