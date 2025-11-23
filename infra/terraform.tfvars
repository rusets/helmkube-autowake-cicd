# -------------------- Basic project configuration --------------------
region       = "us-east-1"
project_name = "helmkube-autowake"

# -------------------- Application image --------------------
image_tag = "v1.2.2"

# ⚠ Admin IP (keep local; do not commit real value)
admin_ip = "97.138.249.119/32"

# Public NodePort for app
node_port = 30080

# Dashboards restricted to your IP (still gated by admin_ip)
expose_grafana      = true
expose_prometheus   = true
expose_alertmanager = false

# -------------------- EC2 configuration --------------------
instance_type = "m7i-flex.large"
key_name      = null # SSM-only (no SSH key)

# -------------------- Auto-detect EC2 instance --------------------
# Must match actual EC2 Name tag of your k3s node
instance_name_tag = "helmkube-autowake-k3s"
instance_id       = null # let autodetect by Name tag

# -------------------- Auto-wake & auto-sleep settings --------------------
# Leave null: Lambda derives Public DNS/IP automatically
target_url         = null
health_url         = null
idle_minutes       = 5
heartbeat_param    = "/neon-portfolio/last_heartbeat"
expose_sleep_route = false

# -------------------- Access configuration --------------------
# CIDR allowed to reach k3s API (you can tighten later)
admin_cidr     = ["0.0.0.0/0"]
use_ssm_deploy = false
