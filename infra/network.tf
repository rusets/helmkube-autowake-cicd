############################################
# Default VPC & Subnets (data sources)
############################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


############################################
# Admin IP list (from var.admin_ip) — empty means “no admin-only rules”
##############################################
locals {
  # Normalize input: nil-safe + trim spaces
  admin_ip_clean = var.admin_ip != null ? trimspace(var.admin_ip) : ""

  # Build list only when value provided (else empty list)
  admin_ip_list = local.admin_ip_clean != "" ? [local.admin_ip_clean] : []
}

############################################
# Security Group for k3s node
# - App NodePort: public (e.g., 30080/30800)
# - k3s API/Grafana/Prometheus/Alertmanager: admin IP only (if provided)
############################################
resource "aws_security_group" "k3s_sg" {
  name        = "${var.project_name}-k3s-sg"
  description = "k3s API, public app NodePort, admin-only dashboards"
  vpc_id      = data.aws_vpc.default.id

  # k3s API — admin IP only
  dynamic "ingress" {
    for_each = length(local.admin_ip_list) > 0 ? [1] : []
    content {
      description = "k3s API (admin only)"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = local.admin_ip_list
    }
  }

  # App NodePort — public
  ingress {
    description = "App NodePort (public)"
    from_port   = var.node_port
    to_port     = var.node_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana — admin IP only (behind toggle)
  dynamic "ingress" {
    for_each = (var.expose_grafana && length(local.admin_ip_list) > 0) ? [1] : []
    content {
      description = "Grafana (admin only)"
      from_port   = var.grafana_node_port
      to_port     = var.grafana_node_port
      protocol    = "tcp"
      cidr_blocks = local.admin_ip_list
    }
  }

  # Prometheus — admin IP only (behind toggle)
  dynamic "ingress" {
    for_each = (var.expose_prometheus && length(local.admin_ip_list) > 0) ? [1] : []
    content {
      description = "Prometheus (admin only)"
      from_port   = var.prometheus_node_port
      to_port     = var.prometheus_node_port
      protocol    = "tcp"
      cidr_blocks = local.admin_ip_list
    }
  }

  # Alertmanager — admin IP only (optional toggle)
  dynamic "ingress" {
    for_each = (try(var.expose_alertmanager, false) && length(local.admin_ip_list) > 0) ? [1] : []
    content {
      description = "Alertmanager (admin only)"
      from_port   = 30992
      to_port     = 30992
      protocol    = "tcp"
      cidr_blocks = local.admin_ip_list
    }
  }

  # Full egress (SSM, package installs, ECR pulls, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-k3s-sg"
    Project = var.project_name
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [description]
  }
}
