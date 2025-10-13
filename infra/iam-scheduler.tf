###############################
# EventBridge Scheduler → Lambda
# Автосон каждые 1 мин проверяет idle и останавливает EC2,
# если нет heartbeat ≥ var.idle_minutes (по логике sleep_instance.py)
###############################

# Роль для EventBridge Scheduler
data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler_role" {
  name               = "${var.project_name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
}

# Разрешаем Scheduler вызывать КОНКРЕТНУЮ Lambda sleep_instance
data "aws_iam_policy_document" "scheduler_invoke_lambda" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.sleep_instance.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda_attach" {
  role   = aws_iam_role.scheduler_role.id
  policy = data.aws_iam_policy_document.scheduler_invoke_lambda.json
}

# График: раз в минуту вызывать sleep_instance
resource "aws_scheduler_schedule" "sleep_every_min" {
  name                = "${var.project_name}-sleep-every-minute"
  description         = "Call sleep_instance every minute to stop EC2 after ${var.idle_minutes} minutes idle"
  schedule_expression = "rate(1 minute)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.sleep_instance.arn
    role_arn = aws_iam_role.scheduler_role.arn
    # при необходимости можно передать параметры в handler через input
    input = jsonencode({})
  }

  # опционально: привязать к определённой зоне (Region) аккаунта
  # state = "ENABLED"
}


