resource "null_resource" "fetch_kubeconfig" {
  count = var.use_ssm_deploy ? 0 : 1

  triggers = {
    instance_id = aws_instance.k3s.id
    region      = var.region
    out_path    = var.kubeconfig_path
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

# --- ECR secret via kubectl (после fetch_kubeconfig) ---
resource "null_resource" "apply_ecr_secret" {
  count      = var.use_ssm_deploy ? 0 : 1
  depends_on = [null_resource.fetch_kubeconfig]

  # триггеры, чтобы secret переезжал при смене репо/региона
  triggers = {
    repo_url = aws_ecr_repository.hello.repository_url
    region   = var.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOC
      set -euo pipefail
      K="${var.kubeconfig_path}"

      # получаем реестр из полного URL репозитория ECR
      ECR_HOST="$(echo "${aws_ecr_repository.hello.repository_url}" | cut -d/ -f1)"

      # создаём/обновляем секрет docker-registry с паролем ECR
      kubectl --kubeconfig "$K" -n default create secret docker-registry ecr-dockercfg \
        --docker-server="$ECR_HOST" \
        --docker-username="AWS" \
        --docker-password="$(aws ecr get-login-password --region ${var.region})" \
        --dry-run=client -o yaml | kubectl --kubeconfig "$K" apply -f -

      # контроль
      kubectl --kubeconfig "$K" -n default get secret ecr-dockercfg -o yaml >/dev/null
    EOC
  }
}

# --- Helm deploy (upgrade --install) ---
resource "null_resource" "helm_deploy_hello" {
  count      = var.use_ssm_deploy ? 0 : 1
  depends_on = [null_resource.apply_ecr_secret]

  # переустановка при смене тега/порта/репо
  triggers = {
    image_repo = aws_ecr_repository.hello.repository_url
    image_tag  = var.image_tag
    node_port  = var.node_port
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOC
      set -euo pipefail
      K="${var.kubeconfig_path}"
      CHART_PATH="${path.module}/../charts/hello"

      # формируем values.yaml на лету, чтобы явно задать NodePort 30080 и secret
      TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
      cat > "$TMPDIR/values.yaml" <<YAML
image:
  repository: ${aws_ecr_repository.hello.repository_url}
  tag: ${var.image_tag}
  pullPolicy: Always
imagePullSecrets:
  - name: ecr-dockercfg
service:
  type: NodePort
  port: 80
  targetPort: 3000
  nodePort: ${var.node_port}
livenessProbe:
  httpGet: { path: "/", port: 3000 }
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3
readinessProbe:
  httpGet: { path: "/", port: 3000 }
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3
YAML

      # надёжный деплой с ожиданием готовности
      helm --kubeconfig "$K" upgrade --install hello "$CHART_PATH" \
        -n default -f "$TMPDIR/values.yaml" --wait --timeout 10m

      # контроль
      kubectl --kubeconfig "$K" -n default get svc,deploy,pods -o wide
    EOC
  }
}