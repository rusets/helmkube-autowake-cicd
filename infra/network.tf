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
# Admin IP list (from var.admin_ip)
# Empty string => no admin-only rules
############################################
locals {
  admin_ip_clean = var.admin_ip != null ? trimspace(var.admin_ip) : ""
  admin_ip_list  = local.admin_ip_clean != "" ? [local.admin_ip_clean] : []
}

############################################
# Security Group — k3s node perimeter
# - 10250 (kubelet metrics) from VPC CIDR
# - 6443 from VPC CIDR (pods via ClusterIP) + admin /32
# - App NodePort public
# - Grafana/Prometheus/Alertmanager only from admin /32 (toggles)
############################################
resource "aws_security_group" "k3s_sg" {
  name        = "${var.project_name}-k3s-sg"
  description = "k3s API, public app NodePort, admin-only dashboards"
  vpc_id      = data.aws_vpc.default.id

  # k3s API from VPC CIDR (pods -> API server via ClusterIP)
  ingress {
    description = "k3s API from VPC CIDR (pods via ServiceIP)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # kubelet metrics from VPC CIDR (Prometheus scrape 10250)
  ingress {
    description = "Kubelet metrics from VPC CIDR (Prometheus scrape 10250)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # k3s API admin-only (/32) when provided
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

  # Grafana — admin-only
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

  # Prometheus — admin-only
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

  # Alertmanager — admin-only (toggle)
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

  # Full egress
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
