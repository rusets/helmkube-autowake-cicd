############################################
# CloudWatch Log Group — SSM association logs
# Purpose: centralize outputs from SSM association runs
# Retention: 14 days to control costs and keep recent history
############################################
resource "aws_cloudwatch_log_group" "ssm_assoc" {
  name              = "/ssm/assoc/${var.project_name}"
  retention_in_days = 14

  tags = {
    Project = var.project_name
  }
}
