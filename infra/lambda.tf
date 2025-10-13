############################################
# Lambda + IAM (safe instance/urls resolve)
############################################

locals {
  # Могут отсутствовать на ранних стадиях, поэтому try(...)
  k3s_id_maybe  = try(aws_instance.k3s.id, null)
  k3s_dns_maybe = try(aws_instance.k3s.public_dns, null)


  # Итоговый INSTANCE_ID: var > k3s > autodetect > "MISSING" (чтобы не падать на plan/destroy)
  instance_id_effective = (
    var.instance_id != null ? var.instance_id :
    (local.k3s_id_maybe != null ? local.k3s_id_maybe :
    (local.autodetected_instance_id != null ? local.autodetected_instance_id : "MISSING"))
  )

  # Если var.target_url не задан — соберём из DNS k3s + node_port
  target_url_auto      = (local.k3s_dns_maybe != null ? "http://${local.k3s_dns_maybe}:${var.node_port}/" : null)
  target_url_effective = coalesce(var.target_url, local.target_url_auto)

  # HEALTH_URL: var.health_url > target_url_effective
  health_url_effective = coalesce(var.health_url, local.target_url_effective)
}

# ---------- IAM для Lambda ----------
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_ec2_ssm" {
  name = "${var.project_name}-lambda-ec2-ssm"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ec2:DescribeInstances", "ec2:StartInstances", "ec2:StopInstances"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:PutParameter"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ec2_ssm" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ec2_ssm.arn
}

# ---------- wake lambda (/, /status, /heartbeat) ----------
resource "aws_lambda_function" "wake_instance" {
  function_name    = "${var.project_name}-wake"
  role             = aws_iam_role.lambda_role.arn
  handler          = "wake_instance.handler"
  runtime          = "python3.11"
  filename         = "${path.module}/wake_instance.zip"
  source_code_hash = filebase64sha256("${path.module}/wake_instance.zip")
  timeout          = 30

  # Если В ЭТОМ МОДУЛЕ есть aws_instance.k3s — оставь; иначе удали строку.
  depends_on = [aws_instance.k3s]

  environment {
    variables = {
      INSTANCE_ID     = local.instance_id_effective
      TARGET_URL      = local.target_url_effective
      HEALTH_URL      = local.health_url_effective
      IDLE_MINUTES    = tostring(var.idle_minutes)
      HEARTBEAT_PARAM = var.heartbeat_param
    }
  }
}

# ---------- sleep lambda (Scheduler дергает каждую минуту) ----------
resource "aws_lambda_function" "sleep_instance" {
  function_name    = "${var.project_name}-sleep"
  role             = aws_iam_role.lambda_role.arn
  handler          = "sleep_instance.handler"
  runtime          = "python3.11"
  filename         = "${path.module}/sleep_instance.zip"
  source_code_hash = filebase64sha256("${path.module}/sleep_instance.zip")
  timeout          = 30

  # Если В ЭТОМ МОДУЛЕ есть aws_instance.k3s — оставь; иначе удали строку.
  depends_on = [aws_instance.k3s]

  environment {
    variables = {
      INSTANCE_ID     = local.instance_id_effective
      IDLE_MINUTES    = tostring(var.idle_minutes)
      HEARTBEAT_PARAM = var.heartbeat_param
      GRACE_MINUTES   = "7" # защита от преждевременного stop во время провижининга
    }
  }
}