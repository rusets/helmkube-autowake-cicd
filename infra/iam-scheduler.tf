############################################
# EventBridge Scheduler → periodic EC2 reaper
# Purpose: invoke sleep Lambda each minute to enforce idle shutdown
############################################

# Trust policy for EventBridge Scheduler
data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

# IAM role assumed by EventBridge Scheduler
resource "aws_iam_role" "scheduler_role" {
  name               = "${var.project_name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
}

# Inline policy: allow Scheduler to invoke the specific sleep Lambda
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

# Scheduler rule: call sleep_instance once per minute (initially disabled)
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
    input    = jsonencode({})
  }

  state = "ENABLED"
}
