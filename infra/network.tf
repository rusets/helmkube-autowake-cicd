############################################
# Default VPC and Subnets
# Purpose: fetch default AWS VPC and its subnets for networking context
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
# Admin IP Normalization
# Purpose: ensure admin_ip is usable as /32 list or empty
############################################
locals {
  admin_ip_clean = var.admin_ip != null ? trimspace(var.admin_ip) : ""
  admin_ip_list  = local.admin_ip_clean != "" ? [local.admin_ip_clean] : []
}

############################################
# Security Group — k3s Node Perimeter
# Purpose: expose API, NodePort app, metrics, dashboards
############################################
resource "aws_security_group" "k3s_sg" {
  name        = "${var.project_name}-k3s-sg"
  description = "k3s API, public app NodePort, admin-only dashboards"
  vpc_id      = data.aws_vpc.default.id

  ############################################
  # k3s API — intra-VPC access for pods/services
  ############################################
  ingress {
    description = "k3s API from VPC CIDR (pods via ServiceIP)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  ############################################
  # k3s API — public EIP /32 required for API-server metrics scrape
  ############################################
  ingress {
    description = "k3s API (self-scrape EIP for Prometheus metrics)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["54.88.152.10/32"]
  }

  ############################################
  # Kubelet metrics — Prometheus access from VPC only
  ############################################
  ingress {
    description = "Kubelet metrics from VPC CIDR (Prometheus scrape 10250)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  ############################################
  # k3s API — admin-only direct access from home IP
  ############################################
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

  ############################################
  # NodePort application — publicly accessible
  ############################################
  #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  ingress {
    description = "App NodePort (public)"
    from_port   = var.node_port
    to_port     = var.node_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ############################################
  # Grafana dashboard — admin-only access
  ############################################
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

  ############################################
  # Prometheus dashboard — admin-only access
  ############################################
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

  ############################################
  # Alertmanager dashboard — admin-only access
  ############################################
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

  ############################################
  # Outbound — allow any destination
  ############################################
  #tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "Allow all outbound traffic from k3s node"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ############################################
  # Metadata and lifecycle
  ############################################
  tags = {
    Name    = "${var.project_name}-k3s-sg"
    Project = var.project_name
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [description]
  }
}
