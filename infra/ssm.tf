############################################
# SSM parameters (protected & drift-proof)
############################################
# Heartbeat marker the Lambdas will update at runtime.
# We intentionally ignore 'value' drift so TF doesn’t fight the app.

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
