variable "region" {
  type        = string
  description = "AWS region where resources will be deployed."
}

variable "project_name" {
  type        = string
  description = "Project name prefix for tagging and resource naming."
}

variable "github_org" {
  type        = string
  description = "GitHub organization or username (used for OIDC trust)."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name associated with this deployment."
}

variable "image_tag" {
  type        = string
  description = "Docker image tag for the ECR repository."
  default     = "latest"
}

variable "node_port" {
  type        = number
  description = "Kubernetes NodePort for the service."
  validation {
    condition     = var.node_port >= 30000 && var.node_port <= 32767
    error_message = "node_port must be in the Kubernetes NodePort range 30000–32767."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the k3s node (e.g., t3.small)."
  default     = "t3.small"
}

variable "admin_cidr" {
  type        = list(string)
  description = "CIDR list allowed to reach SSH(22) and k3s API(6443)."
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  type        = string
  description = "Optional EC2 key pair name; null to disable SSH key."
  default     = null
}

variable "github_token" {
  type        = string
  description = "Optional PAT for private GitHub repo; empty if public."
  default     = ""
  sensitive   = true
}

variable "kubeconfig_path" {
  type        = string
  description = "Local path to the kubeconfig used by helm/kubectl providers."
  default     = "./k3s.yaml"
}

variable "use_ssm_deploy" {
  type        = bool
  description = "If true — deploy app via AWS SSM Document (legacy). If false — use Helm directly."
  default     = false
}

variable "expose_sleep_route" {
  type        = bool
  description = "Expose GET /sleep for manual testing (not recommended in prod)."
  default     = false
}

# ==== Автодетект EC2 ====

variable "instance_name_tag" {
  type        = string
  description = "Value of EC2 tag 'Name' to autodetect instance (if instance_id is not set)."
  default     = "helmkube-autowake-ec2"
}

variable "instance_id" {
  type        = string
  description = "EC2 instance ID to start/stop (override autodetect if set)."
  default     = null
}

# ==== Авто-wake/sleep настройки ====

variable "target_url" {
  type        = string
  description = "Public URL of your site (e.g., http://ec2-...:30080/). Used for redirect when instance is running."
}

variable "health_url" {
  type        = string
  description = "Healthcheck URL used by wake Lambda; defaults to target_url."
  default     = null
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