############################################
# Elastic IP lookup
# Purpose: reuse the already allocated EIP for the k3s node
############################################
data "aws_eip" "existing" {
  id = "eipalloc-044ae74e69206a2c0"
}

############################################
# EC2 instance — single k3s node
# Purpose: run K3s with fixed EIP, IAM role, SG, and cloud-init bootstrap
############################################
resource "aws_instance" "k3s" {
  ami                         = data.aws_ssm_parameter.al2023_latest.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.k3s_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = templatefile("${path.root}/../templates/user_data.sh.tmpl", {
    region          = var.region
    node_port       = var.node_port
    ecr_repo_url    = aws_ecr_repository.hello.repository_url
    image_tag       = var.image_tag
    grafana_port    = var.grafana_node_port
    prometheus_port = var.prometheus_node_port
    project_name    = var.project_name
    github_org      = try(var.github_org, null)
    github_repo     = try(var.github_repo, null)
    ecr_repo        = aws_ecr_repository.hello.repository_url
    eip             = data.aws_eip.existing.public_ip
  })

  user_data_replace_on_change = true

  tags = {
    Name       = "${var.project_name}-k3s"
    Project    = var.project_name
    GitHubRepo = try(var.github_repo, null)
    GitHubOrg  = try(var.github_org, null)
  }

  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      ami,
      associate_public_ip_address,
      metadata_options,
    ]
  }
}

############################################
# Elastic IP association
# Purpose: attach existing EIP to the instance on every wake
############################################
resource "aws_eip_association" "k3s" {
  allocation_id       = data.aws_eip.existing.id
  instance_id         = aws_instance.k3s.id
  allow_reassociation = true
}
