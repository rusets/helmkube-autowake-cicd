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
# Instance type, API access CIDRs, and SSH key
############################################

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the k3s node (e.g., m7i-flex.large)."
  default     = "m7i-flex.large"
}

variable "admin_cidr" {
  type        = list(string)
  description = "CIDR list allowed to reach the k3s API (6443)."
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.admin_cidr) > 0 && alltrue([for c in var.admin_cidr : can(cidrnetmask(c))])
    error_message = "admin_cidr must be a non-empty list of valid CIDR blocks."
  }
}

variable "key_name" {
  type        = string
  description = "Optional EC2 key pair name; null disables SSH key access."
  default     = null
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
# GitHub & CI/CD
# PAT is optional; keep empty for public repos
############################################

variable "github_token" {
  type        = string
  description = "Optional GitHub PAT for private repos; empty if public."
  default     = ""
  sensitive   = true
}

############################################
# Wake/Sleep & Monitoring
# App URLs, heartbeat, timeouts, and polling windows
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

variable "local_tz" {
  type        = string
  description = "Timezone for ETA text on the waiting page."
  default     = "America/Chicago"
}

variable "healthcheck_timeout_sec" {
  type        = number
  description = "HTTP healthcheck timeout per probe."
  default     = 3.5
}

variable "dns_wait_total_sec" {
  type        = number
  description = "How long to wait for PublicDnsName to appear after start."
  default     = 60
}

variable "ready_poll_total_sec" {
  type        = number
  description = "Total budget to poll app readiness before showing waiting page."
  default     = 240
}

variable "ready_poll_interval_sec" {
  type        = number
  description = "Interval between readiness probes."
  default     = 3.0
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
# SSM (manual reference only)
# Key under which kubeconfig is stored
############################################

variable "kubeconfig_param_name" {
  type        = string
  description = "SSM Parameter Store key where kubeconfig is stored (manual upload)."
  default     = "/helmkube/k3s/kubeconfig"
}

############################################
# Optional / Safety
# Deployment mode, ID overrides, protections, routes
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

variable "protect" {
  description = "Protect critical resources from destroy."
  type        = bool
  default     = true
}

variable "expose_sleep_route" {
  type        = bool
  description = "Expose GET /sleep route in API Gateway (for manual testing)."
  default     = false
}

variable "instance_name_tag" {
  type        = string
  description = "Value of EC2 Name tag used to autodetect instance (data.aws_instances.by_name_tag)."
  default     = "helmkube-autowake-ec2"
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

variable "helm_wait" {
  type        = bool
  description = "Whether Helm should wait for resources to become ready."
  default     = true
}

############################################
# Alertmanager NodePort
# Fixed NodePort to keep dashboards consistent
############################################

variable "alertmanager_node_port" {
  type        = number
  description = "NodePort for Alertmanager (30000–32767)."
  default     = 30992
  validation {
    condition     = var.alertmanager_node_port >= 30000 && var.alertmanager_node_port <= 32767
    error_message = "alertmanager_node_port must be in 30000–32767."
  }
}
