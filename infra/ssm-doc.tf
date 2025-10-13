resource "aws_ssm_document" "app_deploy" {
  count         = var.use_ssm_deploy ? 1 : 0
  name          = "${var.project_name}-helm-deploy-v2"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy NodePort service using ECR image (via kubectl) with ECR pull secret"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "DeployWithECRSecret"
      inputs = {
        runCommand = [
          "set -euo pipefail",
          "REGION='${var.region}'",
          "export AWS_DEFAULT_REGION=\"$REGION\"",
          "K='kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml'",
          "for i in $(seq 1 60); do if $K get --raw=/readyz >/dev/null 2>&1; then echo 'k3s API ready'; break; fi; echo 'waiting for k3s API...'; sleep 5; done",
          "sudo dnf -y install awscli >/dev/null 2>&1 || true",
          "ECR_REGISTRY=\"$(echo '${aws_ecr_repository.hello.repository_url}' | cut -d/ -f1)\"",
          "ECR_PASS=\"$(aws ecr get-login-password --region \"$REGION\")\"",
          "$K delete secret ecr-dockercfg -n default --ignore-not-found",
          "$K create secret docker-registry ecr-dockercfg -n default --docker-server=\"$ECR_REGISTRY\" --docker-username=AWS --docker-password=\"$ECR_PASS\"",
          "$K patch serviceaccount default -n default --type merge -p '{\"imagePullSecrets\":[{\"name\":\"ecr-dockercfg\"}]}' || true",
          "cat >/tmp/app.yaml <<'EOF'",
          "apiVersion: apps/v1",
          "kind: Deployment",
          "metadata:",
          "  name: hello",
          "  namespace: default",
          "spec:",
          "  replicas: 1",
          "  selector:",
          "    matchLabels: { app: hello }",
          "  template:",
          "    metadata:",
          "      labels: { app: hello }",
          "    spec:",
          "      imagePullSecrets:",
          "      - name: ecr-dockercfg",
          "      containers:",
          "      - name: hello",
          "        image: ${aws_ecr_repository.hello.repository_url}:${var.image_tag}",
          "        ports: [{ containerPort: 3000 }]",
          "        imagePullPolicy: Always",
          "        readinessProbe:",
          "          httpGet:",
          "            path: /",
          "            port: 3000",
          "          initialDelaySeconds: 5",
          "          periodSeconds: 5",
          "          timeoutSeconds: 2",
          "          failureThreshold: 3",
          "        livenessProbe:",
          "          httpGet:",
          "            path: /",
          "            port: 3000",
          "          initialDelaySeconds: 15",
          "          periodSeconds: 10",
          "          timeoutSeconds: 2",
          "          failureThreshold: 3",
          "---",
          "apiVersion: v1",
          "kind: Service",
          "metadata:",
          "  name: hello-svc",
          "  namespace: default",
          "spec:",
          "  type: NodePort",
          "  selector: { app: hello }",
          "  ports:",
          "  - name: http",
          "    port: 80",
          "    targetPort: 3000",
          "    nodePort: ${var.node_port}",
          "EOF",
          "$K apply -f /tmp/app.yaml",
          "$K rollout status deploy/hello -n default --timeout=180s || true",
          "$K get pods -n default -o wide || true",
          "$K get svc  -n default -o wide || true"
        ]
      }
    }]
  })
}