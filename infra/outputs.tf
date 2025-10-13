output "wake_api_url" {
  value       = aws_apigatewayv2_api.wake_api.api_endpoint
  description = "HTTP API endpoint for wake/sleep control."
}

output "ecr_repo_url" {
  value       = aws_ecr_repository.hello.repository_url
  description = "ECR repository URL for the hello application image."
}

output "ec2_public_dns" {
  value       = aws_instance.k3s.public_dns
  description = "Public DNS name of the k3s EC2 instance."
}

output "ec2_public_ip" {
  value       = aws_instance.k3s.public_ip
  description = "Public IP address of the k3s EC2 instance."
}

output "gha_role_arn" {
  value       = aws_iam_role.gha_role.arn
  description = "IAM Role ARN for GitHub Actions OIDC trust."
}

output "scheduler_role_arn" {
  value       = aws_iam_role.scheduler_role.arn
  description = "IAM Role ARN for AWS Scheduler."
}

output "node_port" {
  value       = var.node_port
  description = "Kubernetes NodePort used by the hello service."
}

output "ssm_assoc_log_group" {
  value       = aws_cloudwatch_log_group.ssm_assoc.name
  description = "CloudWatch Log Group for SSM association output."
}
output "ssm_association_id" {
  description = "Association ID when SSM deploy is enabled"
  value       = try(aws_ssm_association.app_deploy_once[0].id, null)
}

output "s3_assoc_bucket" {
  value = aws_s3_bucket.assoc_logs.bucket
}

output "hello_url_hint" {
  value = "http://${aws_instance.k3s.public_dns}:${var.node_port}/"
}

output "instance_id_effective" {
  value       = local.instance_id_effective
  description = "EC2 Instance ID used (var.instance_id or autodetected by Name tag)."
}

output "autodetected_ids_by_tag" {
  value       = data.aws_instances.by_name_tag.ids
  description = "All EC2 instance IDs matched by tag Name=instance_name_tag (debug)."
}