############################################
# Global & Common
# Naming, GitHub metadata, and image tag
############################################

variable "project_name" {
  type        = string
  description = "Project name prefix for tagging and resource naming."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name: 3–32 chars, lowercase letters, digits and dashes; must start/end with alnum."
  }
}

variable "github_org" {
  type        = string
  default     = "rusets"
  description = "GitHub organization or username (used in tags/metadata)."
}

variable "github_repo" {
  type        = string
  default     = "helmkube-autowake-cicd"
  description = "GitHub repository name (used in tags/metadata)."
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Docker image tag for the ECR repository."
  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag cannot be empty."
  }
}

############################################
# EC2 / Network
# Instance type and NodePorts
############################################

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the k3s node (e.g., m7i-flex.large)."
  default     = "m7i-flex.large"
}

############################################
# Kubernetes
# NodePorts for app + monitoring
############################################

variable "node_port" {
  type        = number
  description = "Kubernetes NodePort for the app (30000–32767)."
  default     = 30080
  validation {
    condition     = var.node_port >= 30000 && var.node_port <= 32767
    error_message = "node_port must be in the Kubernetes NodePort range 30000–32767."
  }
}

variable "grafana_node_port" {
  type        = number
  description = "NodePort for Grafana (30000–32767)."
  default     = 30090
  validation {
    condition     = var.grafana_node_port >= 30000 && var.grafana_node_port <= 32767
    error_message = "grafana_node_port must be in 30000–32767."
  }
}

variable "prometheus_node_port" {
  type        = number
  description = "NodePort for Prometheus (30000–32767)."
  default     = 30991
  validation {
    condition     = var.prometheus_node_port >= 30000 && var.prometheus_node_port <= 32767
    error_message = "prometheus_node_port must be in 30000–32767."
  }
}

############################################
# Wake/Sleep & Monitoring
# App URLs, heartbeat, idle window
############################################

variable "target_url" {
  type        = string
  description = "Public URL of your app (e.g., http://ec2-...:30080/). Leave null to auto-detect from EC2 DNS + node_port."
  default     = null
  validation {
    condition     = var.target_url == null || can(regex("^https?://", var.target_url))
    error_message = "target_url must start with http:// or https:// (or be null)."
  }
}

variable "health_url" {
  type        = string
  description = "Healthcheck URL used by the wake Lambda; defaults to target_url."
  default     = null
  validation {
    condition     = var.health_url == null || can(regex("^https?://", var.health_url))
    error_message = "health_url must start with http:// or https:// (or be null)."
  }
}

variable "idle_minutes" {
  type        = number
  description = "Minutes of inactivity before EC2 is stopped by sleep Lambda."
  default     = 5
  validation {
    condition     = var.idle_minutes >= 1 && var.idle_minutes <= 60
    error_message = "idle_minutes must be between 1 and 60."
  }
}

variable "heartbeat_param" {
  type        = string
  description = "SSM Parameter name storing last heartbeat timestamp."
  default     = "/neon-portfolio/last_heartbeat"
}

############################################
# API & Domain
# Optional custom domain for API Gateway
############################################

variable "api_custom_domain" {
  type        = string
  description = "Custom domain name for API Gateway."
  default     = "app.helmkube.site"
}

############################################
# Optional / Safety
# Deployment mode, ID overrides, routes
############################################

variable "use_ssm_deploy" {
  type        = bool
  description = "If true — deploy app via SSM (kubectl on the node). If false — use Helm provider directly."
  default     = false
}

variable "instance_id" {
  type        = string
  description = "Optional EC2 instance ID to override autodetect."
  default     = null
}

variable "expose_sleep_route" {
  type        = bool
  description = "Expose GET /sleep route in API Gateway (for manual testing)."
  default     = false
}


############################################
# Admin IP (sensitive in tfvars)
# Keep real /32 only in terraform.tfvars (do not commit)
############################################

variable "admin_ip" {
  type        = string
  description = "Your public IPv4 /32 in the form A.B.C.D/32. Keep the real value only in terraform.tfvars (do not commit)."
  default     = null
  validation {
    condition     = var.admin_ip == null || can(regex("^\\d{1,3}(?:\\.\\d{1,3}){3}/32$", trimspace(var.admin_ip)))
    error_message = "admin_ip must be an IPv4 /32 like A.B.C.D/32."
  }
}

############################################
# Monitoring exposure flags
# UIs still gated by admin_ip via security group
############################################

variable "expose_grafana" {
  type        = bool
  description = "Expose Grafana NodePort (still restricted to admin_ip)."
  default     = true
}

variable "expose_prometheus" {
  type        = bool
  description = "Expose Prometheus NodePort (still restricted to admin_ip)."
  default     = true
}

variable "expose_alertmanager" {
  type        = bool
  description = "Expose Alertmanager NodePort (restricted to admin_ip). Keep false unless you really need the UI."
  default     = false
}
