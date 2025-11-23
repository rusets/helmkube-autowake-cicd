############################################
# CloudWatch Log Group — central storage for SSM association logs
############################################
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "ssm_assoc" {
  name              = "/ssm/assoc/${var.project_name}"
  retention_in_days = 14

  tags = {
    Project = var.project_name
  }
}
