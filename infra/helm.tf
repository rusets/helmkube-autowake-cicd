############################################
# Fetch kubeconfig from k3s node via SSM
# Purpose: pull k3s.yaml, rewrite server to public host, wait for /readyz
############################################
resource "null_resource" "fetch_kubeconfig" {
  count = var.use_ssm_deploy ? 0 : 1

  triggers = {
    instance_id = aws_instance.k3s.id
    region      = var.region
    out_path    = coalesce(var.kubeconfig_path, "${path.module}/build/k3s-embed.yaml")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOC
      set -euo pipefail
      export AWS_PAGER=""

      INST="${aws_instance.k3s.id}"
      REGION="${var.region}"
      OUT="${var.kubeconfig_path}"

      aws ec2 wait instance-running   --region "$REGION" --instance-ids "$INST"
      aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INST"

      for i in $(seq 1 40); do
        if CID=$(aws ssm send-command \
          --region "$REGION" \
          --instance-ids "$INST" \
          --document-name "AWS-RunShellScript" \
          --parameters commands='echo ssm-ready' \
          --query 'Command.CommandId' --output text 2>/tmp/ssm.err); then
          break
        fi
        sleep 6
      done

      for j in $(seq 1 30); do
        STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$INST" --query 'Status' --output text || true)
        [ "$STATUS" = "Success" ] && break
        case "$STATUS" in Failed|Cancelled|TimedOut) echo "SSM warmup failed: $STATUS" >&2; exit 1;; esac
        sleep 2
      done

      for i in $(seq 1 60); do
        CID=$(aws ssm send-command \
          --region "$REGION" \
          --instance-ids "$INST" \
          --document-name "AWS-RunShellScript" \
          --parameters commands='test -s /etc/rancher/k3s/k3s.yaml && echo ready || echo wait' \
          --query 'Command.CommandId' --output text)
        sleep 3
        RESULT=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$INST" --query 'StandardOutputContent' --output text || true)
        [ "$RESULT" = "ready" ] && break
        sleep 3
      done

      CID=$(aws ssm send-command \
        --region "$REGION" \
        --instance-ids "$INST" \
        --document-name "AWS-RunShellScript" \
        --parameters commands='sudo cat /etc/rancher/k3s/k3s.yaml' \
        --query 'Command.CommandId' --output text)

      for i in $(seq 1 30); do
        STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$INST" --query 'Status' --output text || true)
        case "$STATUS" in Success) break ;; Failed|Cancelled|TimedOut) echo "SSM command failed: $STATUS" >&2; exit 1 ;; esac
        sleep 2
      done

      CONTENT=$(aws ssm get-command-invocation \
        --region "$REGION" \
        --command-id "$CID" \
        --instance-id "$INST" \
        --query 'StandardOutputContent' \
        --output text)

      if [ -z "$CONTENT" ] || ! echo "$CONTENT" | grep -q '^apiVersion:'; then
        echo "Invalid kubeconfig" >&2
        exit 1
      fi

      echo "$CONTENT" > "$OUT"
      chmod 600 "$OUT"

      PUB_DNS=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INST" --query 'Reservations[0].Instances[0].PublicDnsName' --output text || true)
      PUB_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INST" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text || true)
      HOST="$${PUB_DNS:-$${PUB_IP}}"

      if [ -n "$HOST" ]; then
        python3 - "$OUT" "$HOST" <<'PY'
import re, sys
path, host = sys.argv[1], sys.argv[2]
data = open(path, encoding="utf-8").read()
data = re.sub(r'(server:\s*https?://)127\.0\.0\.1:6443', r'\1'+host+':6443', data)
open(path, "w", encoding="utf-8").write(data)
PY
      fi

      ok=0
      for i in $(seq 1 60); do
        if kubectl --kubeconfig "$OUT" get --raw=/readyz >/dev/null 2>&1; then
          ok=$((ok+1))
          [ $ok -ge 3 ] && break
        else
          ok=0
        fi
        sleep 5
      done

      kubectl --kubeconfig "$OUT" get nodes -o wide || true
    EOC
  }
}

############################################
# ECR Docker auth secret (cluster)
# Purpose: create/refresh ecr-dockercfg in default namespace via kubectl
############################################
resource "null_resource" "apply_ecr_secret" {
  count      = var.use_ssm_deploy ? 0 : 1
  depends_on = [null_resource.fetch_kubeconfig]

  triggers = {
    repo_url = aws_ecr_repository.hello.repository_url
    region   = var.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOC
      set -euo pipefail
      K="${var.kubeconfig_path}"

      ECR_HOST="$(echo "${aws_ecr_repository.hello.repository_url}" | cut -d/ -f1)"

      kubectl --kubeconfig "$K" -n default create secret docker-registry ecr-dockercfg \
        --docker-server="$ECR_HOST" \
        --docker-username="AWS" \
        --docker-password="$(aws ecr get-login-password --region ${var.region})" \
        --dry-run=client -o yaml | kubectl --kubeconfig "$K" apply -f -

      kubectl --kubeconfig "$K" -n default get secret ecr-dockercfg -o yaml >/dev/null
    EOC
  }
}

############################################
# Helm deploy/upgrade "hello" chart
# Purpose: render values.yaml with fixed NodePort and wait for rollout
############################################
resource "null_resource" "helm_deploy_hello" {
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      K="../build/k3s-embed.yaml"
      CHART_PATH="./../charts/hello"

      TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
      cat > "$TMPDIR/values.yaml" <<YAML
image:
  repository: 097635932419.dkr.ecr.us-east-1.amazonaws.com/helmkube-autowake/hello-app
  tag: v1.2.2
  pullPolicy: IfNotPresent
imagePullSecrets:
  - name: ecr-dockercfg
service:
  type: NodePort
  port: 80
  targetPort: 3000
  nodePort: 30080
YAML

      helm --kubeconfig "$K" upgrade --install hello "$CHART_PATH" \
        -n default -f "$TMPDIR/values.yaml" --wait --timeout 10m

      kubectl --kubeconfig "$K" -n default get svc,deploy,pods -o wide
    EOT
  }
}
