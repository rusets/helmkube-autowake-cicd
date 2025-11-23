import json
import os
import datetime
import time
import urllib.request
from urllib.error import HTTPError
import boto3
from zoneinfo import ZoneInfo

EC2 = boto3.client("ec2")
SSM = boto3.client("ssm")

INSTANCE_ID = os.environ["INSTANCE_ID"]
TARGET_URL = os.environ.get("TARGET_URL", "")
HEALTH_URL = os.environ.get("HEALTH_URL", "")
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "5"))
HEARTBEAT_KEY = os.environ.get("HEARTBEAT_PARAM", "/neon-portfolio/last_heartbeat")
NODE_PORT = int(os.environ.get("NODE_PORT", "30080"))
LOCAL_TZ_NAME = os.environ.get("LOCAL_TZ", "America/Chicago")

REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
KUBECONFIG_PARAM = os.environ.get("KUBECONFIG_PARAM", "/helmkube/k3s/kubeconfig")

REFRESH_ECR_ON_WAKE = os.environ.get("REFRESH_ECR_ON_WAKE", "false").lower() in ("1", "true", "yes")
AUTO_UPDATE_KUBECONFIG = os.environ.get("AUTO_UPDATE_KUBECONFIG", "true").lower() in ("1", "true", "yes")

HC_TIMEOUT_S = float(os.environ.get("HEALTHCHECK_TIMEOUT_SEC", "3.5"))
DNS_WAIT_TOTAL_SEC = int(os.environ.get("DNS_WAIT_TOTAL_SEC", "60"))
READY_POLL_TOTAL_SEC = 0
READY_POLL_INTERVAL_SEC = float(os.environ.get("READY_POLL_INTERVAL_SEC", "3.0"))


def _now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def _build_url(host: str, port: int, path: str = "/") -> str:
    if not host:
        return TARGET_URL or HEALTH_URL or "/"
    if not path.startswith("/"):
        path = "/" + path
    url = f"http://{host}:{port}{path}"
    if path == "/" and not url.endswith("/"):
        url += "/"
    return url


def _describe_all():
    r = EC2.describe_instances(InstanceIds=[INSTANCE_ID])
    inst = r["Reservations"][0]["Instances"][0]
    state = inst["State"]["Name"]
    dns = inst.get("PublicDnsName") or ""
    ip = inst.get("PublicIpAddress") or ""
    return state, dns, ip


def _build_target(dns: str | None, ip: str | None) -> str:
    if ip:
        return _build_url(ip, NODE_PORT, "/")
    if dns:
        return _build_url(dns, NODE_PORT, "/")
    return TARGET_URL or HEALTH_URL or "/"


def _probe(url: str, timeout: float, method: str) -> bool:
    try:
        req = urllib.request.Request(url, method=method, headers={"User-Agent": "wake-check"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return 200 <= r.status < 500
    except HTTPError as e:
        return 200 <= e.code < 500
    except Exception:
        return False


def _get_public_http_ok(url: str, timeout: float) -> bool:
    return _probe(url, timeout, "HEAD") or _probe(url, timeout, "GET")


def _start_instance():
    try:
        EC2.start_instances(InstanceIds=[INSTANCE_ID])
    except Exception as e:
        if "IncorrectInstanceState" not in str(e):
            raise


def _put_heartbeat(ts=None):
    if ts is None:
        ts = _now_utc().isoformat()
    SSM.put_parameter(Name=HEARTBEAT_KEY, Value=ts, Type="String", Overwrite=True)


def _resp(status=200, body=None, html=False, headers=None):
    if body is None:
        body = {}
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


def _refresh_ecr_secret_and_restart():
    if not REFRESH_ECR_ON_WAKE:
        return
    try:
        commands = [
            "set -euo pipefail",
            f"REGION='{REGION}'",
            "export AWS_DEFAULT_REGION=\"$REGION\"",
            "K='kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml'",
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
        pass


def _update_kubeconfig_via_ssm():
    if not AUTO_UPDATE_KUBECONFIG:
        return
    try:
        commands = [
            "set -euo pipefail",
            f"REGION='{REGION}'",
            f"KCFG='{KUBECONFIG_PARAM}'",
            "export AWS_DEFAULT_REGION=\"$REGION\"",
            "TOKEN=$(curl -fsX PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')",
            "HOST=$(curl -fsH \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/public-hostname || curl -fsH \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/public-ipv4 || true)",
            "CONTENT=\"$(cat /etc/rancher/k3s/k3s.yaml)\"",
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
        pass


def handler(event, context):
    try:
        http_ctx = event.get("requestContext", {}).get("http", {}) or {}
        raw_path = http_ctx.get("path") or event.get("rawPath") or event.get("path") or "/"
        path_norm = (raw_path.split("?")[0] or "/").rstrip("/") or "/"
        method = http_ctx.get("method", "GET")

        def _is(p: str) -> bool:
            return (path_norm or "/") == (p.rstrip("/") or "/")

        if _is("/heartbeat") and method in ("GET", "POST"):
            _put_heartbeat()
            return _resp(200, {"ok": True, "ts": _now_utc().isoformat()})

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

        if _is("/"):
            if method not in ("GET", "POST"):
                return _resp(405, {"ok": False, "error": "method_not_allowed"})
            try:
                _start_instance()
                _put_heartbeat()
                _update_kubeconfig_via_ssm()
                _refresh_ecr_secret_and_restart()
            except Exception as e:
                return _resp(200, {"ok": False, "error": str(e)})

            target_now = TARGET_URL or HEALTH_URL or "/"
            try:
                state2, dns2, ip2 = _describe_all()
                target_now = _build_target(dns2, ip2) or target_now
            except Exception:
                state2 = "unknown"

            return _resp(200, {"ok": True, "started": True, "target": target_now, "state": state2})

        return _resp(404, {"ok": False, "error": "not_found", "path": path_norm})

    except Exception as e:
        return _resp(200, {"ok": False, "fatal": str(e)})