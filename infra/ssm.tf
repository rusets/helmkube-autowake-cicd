############################################
# SSM Parameter — heartbeat marker updated by Lambdas (drift-tolerant)
############################################
resource "aws_ssm_parameter" "heartbeat" {
  name        = "/neon-portfolio/last_heartbeat"
  description = "Last wake heartbeat timestamp"
  type        = "String"
  value       = "bootstrap"
  tier        = "Standard"

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [value]
  }
}
