############################################
# Locals — safe fallbacks and derived URLs
# Purpose: compute effective instance ID and app URLs without hardcoding
############################################
locals {
  k3s_id_maybe  = try(aws_instance.k3s.id, null)
  k3s_dns_maybe = try(aws_instance.k3s.public_dns, null)

  # Final INSTANCE_ID for Lambdas: explicit var → detected k3s → "MISSING"
  instance_id_effective = coalesce(var.instance_id, local.k3s_id_maybe, "MISSING")

  # TARGET/HEALTH URL: explicit var → auto from k3s DNS
  target_url_auto      = local.k3s_dns_maybe != null ? "http://${local.k3s_dns_maybe}:${var.node_port}/" : null
  target_url_effective = coalesce(var.target_url, local.target_url_auto, "")
  health_url_effective = coalesce(var.health_url, local.target_url_effective, "")

  # Base URL for outputs: prefer custom domain if provided
  wake_api_base = var.api_custom_domain != null ? "https://${var.api_custom_domain}" : aws_apigatewayv2_api.wake_api.api_endpoint
}

############################################
# IAM — Lambda execution role and permissions
# Purpose: allow logs, EC2 control, SSM params, and SSM RunCommand
############################################
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_ec2_ssm" {
  name        = "${var.project_name}-lambda-ec2-ssm"
  description = "Allow Lambda to start/stop/describe EC2 + read/write SSM params + SSM RunCommand"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2Basic"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:StartInstances", "ec2:StopInstances"]
        Resource = "*"
      },
      {
        Sid      = "SSMParams"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = "*"
      },
      {
        Sid    = "SSMRunCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ec2_ssm" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ec2_ssm.arn
}

############################################
# Lambda — wake_instance
# Purpose: start EC2, refresh ECR secret, optionally update kubeconfig
############################################
resource "aws_lambda_function" "wake_instance" {
  function_name    = "${var.project_name}-wake"
  role             = aws_iam_role.lambda_role.arn
  handler          = "wake_instance.handler"
  runtime          = "python3.11"
  filename         = "${path.module}/build/wake_instance.zip"
  source_code_hash = filebase64sha256("${path.module}/build/wake_instance.zip")
  timeout          = 30
  memory_size      = 512

  environment {
    variables = {
      INSTANCE_ID     = local.instance_id_effective
      HEARTBEAT_PARAM = var.heartbeat_param
      IDLE_MINUTES    = tostring(var.idle_minutes)
      NODE_PORT       = tostring(var.node_port)
      LOCAL_TZ        = "America/Chicago"

      # Keep empty: Lambda derives IP/DNS via DescribeInstances
      TARGET_URL = ""
      HEALTH_URL = ""

      # Timings
      HEALTHCHECK_TIMEOUT_SEC = "2.5"
      READY_POLL_TOTAL_SEC    = "10"
      READY_POLL_INTERVAL_SEC = "1.5"
      DNS_WAIT_TOTAL_SEC      = "30"

      # Auto-refresh ECR pull secret on wake
      REFRESH_ECR_ON_WAKE = "true"

      # Auto-update kubeconfig in SSM on wake
      AUTO_UPDATE_KUBECONFIG = "true"
      KUBECONFIG_PARAM       = "/helmkube/k3s/kubeconfig"
    }
  }
}

############################################
# Lambda — sleep_instance
# Purpose: stop EC2 when idle for configured minutes (graceful shutdown)
############################################
resource "aws_lambda_function" "sleep_instance" {
  function_name    = "${var.project_name}-sleep"
  role             = aws_iam_role.lambda_role.arn
  handler          = "sleep_instance.handler"
  runtime          = "python3.11"
  filename         = "${path.module}/build/sleep_instance.zip"
  source_code_hash = filebase64sha256("${path.module}/build/sleep_instance.zip")
  timeout          = 30
  depends_on       = [aws_iam_role_policy_attachment.attach_ec2_ssm]

  environment {
    variables = {
      INSTANCE_ID     = local.instance_id_effective
      IDLE_MINUTES    = tostring(var.idle_minutes)
      HEARTBEAT_PARAM = var.heartbeat_param
      GRACE_MINUTES   = "10"
    }
  }
}

############################################
# API Gateway HTTP API — definition + CORS + access logs
############################################
resource "aws_apigatewayv2_api" "wake_api" {
  name          = "${var.project_name}-wake-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins  = ["*"]
    allow_methods  = ["GET", "POST", "OPTIONS"]
    allow_headers  = ["*"]
    expose_headers = []
    max_age        = 3600
  }
}

resource "aws_cloudwatch_log_group" "wake_api_access" {
  name              = "/apigw/${var.project_name}/access"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "wake_stage" {
  api_id      = aws_apigatewayv2_api.wake_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.wake_api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId",
      routeKey       = "$context.routeKey",
      status         = "$context.status",
      errorMessage   = "$context.error.message",
      integrationErr = "$context.integrationErrorMessage",
      integrationLat = "$context.integrationLatency",
      latency        = "$context.responseLatency",
      requestTime    = "$context.requestTime",
      ip             = "$context.identity.sourceIp",
      protocol       = "$context.protocol",
      userAgent      = "$context.identity.userAgent",
      path           = "$context.path"
    })
  }
}

############################################
# API Gateway — Lambda integrations (wake & sleep)
############################################
resource "aws_apigatewayv2_integration" "wake_integration" {
  api_id                 = aws_apigatewayv2_api.wake_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake_instance.invoke_arn
  payload_format_version = "2.0"
  depends_on             = [aws_lambda_function.wake_instance]
}

resource "aws_apigatewayv2_integration" "sleep_integration" {
  api_id                 = aws_apigatewayv2_api.wake_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sleep_instance.invoke_arn
  payload_format_version = "2.0"
  depends_on             = [aws_lambda_function.sleep_instance]
}

############################################
# API Gateway — routes (/, /status, /heartbeat, optional /sleep)
############################################
resource "aws_apigatewayv2_route" "root" {
  api_id     = aws_apigatewayv2_api.wake_api.id
  route_key  = "ANY /"
  target     = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
  depends_on = [aws_apigatewayv2_integration.wake_integration]
}

resource "aws_apigatewayv2_route" "status" {
  api_id     = aws_apigatewayv2_api.wake_api.id
  route_key  = "ANY /status"
  target     = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
  depends_on = [aws_apigatewayv2_integration.wake_integration]
}

resource "aws_apigatewayv2_route" "heartbeat" {
  api_id     = aws_apigatewayv2_api.wake_api.id
  route_key  = "ANY /heartbeat"
  target     = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
  depends_on = [aws_apigatewayv2_integration.wake_integration]
}

resource "aws_apigatewayv2_route" "sleep_route" {
  count      = var.expose_sleep_route ? 1 : 0
  api_id     = aws_apigatewayv2_api.wake_api.id
  route_key  = "GET /sleep"
  target     = "integrations/${aws_apigatewayv2_integration.sleep_integration.id}"
  depends_on = [aws_apigatewayv2_integration.sleep_integration]
}

############################################
# Lambda permissions — allow HTTP API to invoke
############################################
resource "aws_lambda_permission" "apigw_invoke_wake" {
  statement_id  = "AllowInvokeFromHttpApiWake"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake_instance.function_name
  principal     = "apigateway.amazonaws.com"
  # HTTP API requires /*/* pattern (stage + method)
  source_arn = "${aws_apigatewayv2_api.wake_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_sleep" {
  count         = var.expose_sleep_route ? 1 : 0
  statement_id  = "AllowInvokeFromHttpApiSleep"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sleep_instance.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_sleep_any" {
  count         = var.expose_sleep_route ? 1 : 0
  statement_id  = "AllowInvokeFromHttpApiSleepAny"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sleep_instance.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake_api.execution_arn}/*"
  depends_on = [
    aws_apigatewayv2_api.wake_api,
    aws_apigatewayv2_stage.wake_stage,
    aws_apigatewayv2_integration.sleep_integration
  ]
}

############################################
# SSM Document — on-node deploy (for use_ssm_deploy=true)
# Purpose: ensure fixed NodePort, ECR secret, and basic rollout checks
############################################
resource "aws_ssm_document" "app_deploy" {
  count         = var.use_ssm_deploy ? 1 : 0
  name          = "${var.project_name}-helm-deploy-v2"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2",
    description   = "Deploy NodePort service using ECR image (via kubectl) with ECR pull secret",
    mainSteps = [{
      action = "aws:runShellScript",
      name   = "DeployWithECRSecret",
      inputs = {
        runCommand = [
          "set -euo pipefail",
          "REGION='${var.region}'",
          "export AWS_DEFAULT_REGION=\"$REGION\"",
          "K='kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml'",

          # wait for k3s API
          "for i in $(seq 1 90); do if $K get --raw=/readyz >/dev/null 2>&1; then echo \"k3s API ready\"; break; fi; echo 'waiting for k3s API...'; sleep 3; done",

          # ECR secret and imagePullSecrets
          "sudo dnf -y install awscli >/dev/null 2>&1 || true",
          "ECR_REGISTRY=\"$(echo '${aws_ecr_repository.hello.repository_url}' | cut -d/ -f1)\"",
          "ECR_PASS=\"$(aws ecr get-login-password --region \"$REGION\")\"",
          "$K delete secret ecr-dockercfg -n default --ignore-not-found",
          "$K create secret docker-registry ecr-dockercfg -n default --docker-server=\"$ECR_REGISTRY\" --docker-username=AWS --docker-password=\"$ECR_PASS\" --docker-email=none@none || true",
          "$K patch serviceaccount default -n default --type merge -p '{\"imagePullSecrets\":[{\"name\":\"ecr-dockercfg\"}]}' || true",

          # enforce fixed nodePort by recreating Service
          "echo 'Deleting hello-svc (if exists) to enforce fixed nodePort...';",
          "$K delete svc hello-svc -n default --ignore-not-found || true",
          "for i in $(seq 1 30); do if ! $K get svc hello-svc -n default >/dev/null 2>&1; then echo 'hello-svc deleted'; break; fi; echo 'waiting svc deletion...'; sleep 1; done",

          # manifest (Deployment + Service with fixed nodePort)
          "cat >/tmp/app.yaml <<'EOF'",
          "apiVersion: apps/v1",
          "kind: Deployment",
          "metadata: { name: hello, namespace: default, labels: { app: hello } }",
          "spec:",
          "  replicas: 1",
          "  selector: { matchLabels: { app: hello } }",
          "  template:",
          "    metadata: { labels: { app: hello } }",
          "    spec:",
          "      imagePullSecrets: [ { name: ecr-dockercfg } ]",
          "      containers:",
          "      - name: hello",
          "        image: ${aws_ecr_repository.hello.repository_url}:${var.image_tag}",
          "        imagePullPolicy: Always",
          "        ports: [ { containerPort: 3000 } ]",
          "        readinessProbe: { httpGet: { path: /, port: 3000 }, initialDelaySeconds: 5, periodSeconds: 5, timeoutSeconds: 2, failureThreshold: 3 }",
          "        livenessProbe:  { httpGet: { path: /, port: 3000 }, initialDelaySeconds: 15, periodSeconds: 10, timeoutSeconds: 2, failureThreshold: 3 }",
          "---",
          "apiVersion: v1",
          "kind: Service",
          "metadata: { name: hello-svc, namespace: default, labels: { app: hello } }",
          "spec:",
          "  type: NodePort",
          "  selector: { app: hello }",
          "  ports: [ { name: http, port: 80, targetPort: 3000, nodePort: ${var.node_port} } ]",
          "EOF",

          "$K apply -f /tmp/app.yaml",
          "$K rollout status deploy/hello -n default --timeout=180s || true",

          # diagnostics
          "$K get pods -n default -o wide || true",
          "$K get svc  -n default -o wide || true",
          "$K get endpoints hello-svc -n default -o wide || true",

          # final nodePort check
          "echo -n 'final nodePort: '; $K get svc hello-svc -n default -o jsonpath='{.spec.ports[0].nodePort}'; echo",

          # local port probe on node (non-fatal)
          "curl -sS -I --max-time 3 http://127.0.0.1:${var.node_port}/ || true"
        ]
      }
    }]
  })
}
