############################################
# SSM Association — one-time app deploy via kubectl on the node
# - Runs the SSM Document against the k3s instance
# - Streams outputs to S3 (assoc_logs bucket / ssm-assoc prefix)
# - Enabled only when use_ssm_deploy = true
############################################
resource "aws_ssm_association" "app_deploy_once" {
  count            = var.use_ssm_deploy ? 1 : 0
  name             = aws_ssm_document.app_deploy[0].name
  association_name = "${var.project_name}-helm-deploy-assoc"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.k3s.id]
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.assoc_logs.bucket
    s3_key_prefix  = "ssm-assoc"
    s3_region      = var.region
  }

  depends_on = [
    aws_instance.k3s,
    null_resource.docker_build_push,
    aws_iam_role_policy.ssm_assoc_s3_logs_attach
  ]
}
