############################################
# Locals — effective IDs and URLs
# Purpose: derive instance ID, app URLs, and wake API base
############################################
locals {
  k3s_id_maybe  = try(aws_instance.k3s.id, null)
  k3s_dns_maybe = try(aws_instance.k3s.public_dns, null)

  instance_id_effective = coalesce(var.instance_id, local.k3s_id_maybe, "MISSING")

  target_url_auto      = local.k3s_dns_maybe != null ? "http://${local.k3s_dns_maybe}:${var.node_port}/" : null
  target_url_effective = coalesce(var.target_url, local.target_url_auto, "")
  health_url_effective = coalesce(var.health_url, local.target_url_effective, "")

  wake_api_base = var.api_custom_domain != null ? "https://${var.api_custom_domain}" : aws_apigatewayv2_api.wake_api.api_endpoint
}

############################################
# IAM Role — Lambda execution
# Purpose: allow Lambda to be assumed by lambda.amazonaws.com
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

############################################
# IAM Attachment — basic Lambda logging
# Purpose: attach AWSLambdaBasicExecutionRole to lambda_role
############################################
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################################
# IAM Policy — EC2 and SSM for Lambdas
# Purpose: EC2 start/stop/describe + SSM parameters + SSM RunCommand
############################################
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

############################################
# IAM Attachment — EC2+SSM policy to Lambda role
# Purpose: bind lambda_ec2_ssm policy to lambda_role
############################################
resource "aws_iam_role_policy_attachment" "attach_ec2_ssm" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ec2_ssm.arn
}

############################################
# Lambda Function — wake_instance
# Purpose: start EC2, wait for readiness, refresh ECR, update kubeconfig
############################################
resource "aws_lambda_function" "wake_instance" {
  function_name = "${var.project_name}-wake"
  role          = aws_iam_role.lambda_role.arn
  handler       = "wake_instance.handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.wake_instance.output_path
  source_code_hash = data.archive_file.wake_instance.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID     = local.instance_id_effective
      HEARTBEAT_PARAM = var.heartbeat_param
      IDLE_MINUTES    = tostring(var.idle_minutes)
      NODE_PORT       = tostring(var.node_port)
      LOCAL_TZ        = "America/Chicago"

      TARGET_URL = local.target_url_effective
      HEALTH_URL = local.health_url_effective

      HEALTHCHECK_TIMEOUT_SEC = "2.5"
      READY_POLL_TOTAL_SEC    = "10"
      READY_POLL_INTERVAL_SEC = "1.5"
      DNS_WAIT_TOTAL_SEC      = "30"

      REFRESH_ECR_ON_WAKE = "true"

      AUTO_UPDATE_KUBECONFIG = "true"
      KUBECONFIG_PARAM       = "/helmkube/k3s/kubeconfig"
    }
  }
}

############################################
# Lambda Function — sleep_instance
# Purpose: stop EC2 when idle for configured minutes
############################################
resource "aws_lambda_function" "sleep_instance" {
  function_name = "${var.project_name}-sleep"
  role          = aws_iam_role.lambda_role.arn
  handler       = "sleep_instance.handler"
  runtime       = "python3.11"
  timeout       = 30

  filename         = data.archive_file.sleep_instance.output_path
  source_code_hash = data.archive_file.sleep_instance.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.attach_ec2_ssm
  ]

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
# API Gateway — HTTP API definition
# Purpose: expose wake/sleep endpoints with CORS
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

############################################
# CloudWatch Log Group — API access logs
# Purpose: keep structured access logs for HTTP API
############################################
resource "aws_cloudwatch_log_group" "wake_api_access" {
  name              = "/apigw/${var.project_name}/access"
  retention_in_days = 14
}

############################################
# API Gateway Stage — $default
# Purpose: auto-deploy stage with JSON access logging
############################################
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
# API Gateway Integration — wake_instance
# Purpose: connect HTTP API to wake Lambda via AWS_PROXY
############################################
resource "aws_apigatewayv2_integration" "wake_integration" {
  api_id                 = aws_apigatewayv2_api.wake_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake_instance.invoke_arn
  payload_format_version = "2.0"
  depends_on             = [aws_lambda_function.wake_instance]
}

############################################
# API Gateway Integration — sleep_instance
# Purpose: connect HTTP API to sleep Lambda via AWS_PROXY
############################################
resource "aws_apigatewayv2_integration" "sleep_integration" {
  api_id                 = aws_apigatewayv2_api.wake_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sleep_instance.invoke_arn
  payload_format_version = "2.0"
  depends_on             = [aws_lambda_function.sleep_instance]
}

############################################
# API Gateway Routes — wake/status/heartbeat/sleep
# Purpose: map routes to Lambda integrations
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
# Lambda Permission — wake_instance
# Purpose: allow HTTP API to invoke wake Lambda
############################################
resource "aws_lambda_permission" "apigw_invoke_wake" {
  statement_id  = "AllowInvokeFromHttpApiWake"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake_instance.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake_api.execution_arn}/*/*"
}

############################################
# Lambda Permission — sleep_instance (/*/*)
# Purpose: allow HTTP API to invoke sleep Lambda
############################################
resource "aws_lambda_permission" "apigw_invoke_sleep" {
  count         = var.expose_sleep_route ? 1 : 0
  statement_id  = "AllowInvokeFromHttpApiSleep"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sleep_instance.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake_api.execution_arn}/*/*"
}

############################################
# Lambda Permission — sleep_instance (/*)
# Purpose: extra pattern for HTTP API wildcards
############################################
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
# SSM Document — app_deploy
# Purpose: deploy NodePort app with ECR secret and rollout checks
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

          "for i in $(seq 1 90); do if $K get --raw=/readyz >/dev/null 2>&1; then echo \"k3s API ready\"; break; fi; echo 'waiting for k3s API...'; sleep 3; done",

          "sudo dnf -y install awscli >/dev/null 2>&1 || true",
          "ECR_REGISTRY=\"$(echo '${aws_ecr_repository.hello.repository_url}' | cut -d/ -f1)\"",
          "ECR_PASS=\"$(aws ecr get-login-password --region \"$REGION\")\"",
          "$K delete secret ecr-dockercfg -n default --ignore-not-found",
          "$K create secret docker-registry ecr-dockercfg -n default --docker-server=\"$ECR_REGISTRY\" --docker-username=AWS --docker-password=\"$ECR_PASS\" --docker-email=none@none || true",
          "$K patch serviceaccount default -n default --type merge -p '{\"imagePullSecrets\":[{\"name\":\"ecr-dockercfg\"}]}' || true",

          "echo 'Deleting hello-svc (if exists) to enforce fixed nodePort...';",
          "$K delete svc hello-svc -n default --ignore-not-found || true",
          "for i in $(seq 1 30); do if ! $K get svc hello-svc -n default >/dev/null 2>&1; then echo 'hello-svc deleted'; break; fi; echo 'waiting svc deletion...'; sleep 1; done",

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

          "$K get pods -n default -o wide || true",
          "$K get svc  -n default -o wide || true",
          "$K get endpoints hello-svc -n default -o wide || true",

          "echo -n 'final nodePort: '; $K get svc hello-svc -n default -o jsonpath='{.spec.ports[0].nodePort}'; echo",

          "curl -sS -I --max-time 3 http://127.0.0.1:${var.node_port}/ || true"
        ]
      }
    }]
  })
}
