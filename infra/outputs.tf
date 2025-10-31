############################################
# Safe public outputs (only generic info)
############################################

output "region" {
  description = "AWS region used by this deployment"
  value       = var.region
}

output "node_port" {
  description = "Kubernetes NodePort used by the hello service"
  value       = var.node_port
}

output "ecr_repo_url" {
  description = "ECR repository URL for the hello application image"
  value       = aws_ecr_repository.hello.repository_url
  sensitive   = true
}

############################################
# Sensitive outputs (hidden in CLI output)
############################################

output "wake_api_url" {
  description = "HTTP API endpoint for wake/sleep control"
  value       = aws_apigatewayv2_api.wake_api.api_endpoint
  sensitive   = true
}

output "ec2_public_dns" {
  description = "Public DNS of the k3s EC2 instance"
  value       = aws_instance.k3s.public_dns
  sensitive   = true
}

output "ec2_public_ip" {
  description = "Public IP of the k3s EC2 instance"
  value       = aws_instance.k3s.public_ip
  sensitive   = true
}

output "hello_url_hint" {
  description = "App URL for NodePort access"
  value       = "http://${aws_instance.k3s.public_dns}:${var.node_port}/"
  sensitive   = true
}
