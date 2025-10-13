# -------------------- Basic project configuration --------------------
region       = "us-east-1"
project_name = "helmkube-autowake"


# -------------------- Application image --------------------
image_tag = "v1.2.1"
node_port = 30080

# -------------------- EC2 configuration --------------------
instance_type = "t3.small"

# Leave null if connecting via SSM only (no SSH key pair)
key_name = null

# -------------------- Auto-detect EC2 instance --------------------
# EC2 instance will be found automatically by tag Name = "helmkube-autowake-ec2"
instance_name_tag = "helmkube-autowake-ec2"
instance_id       = null

# -------------------- Auto-wake & auto-sleep settings --------------------
target_url         = "http://ec2-3-231-224-142.compute-1.amazonaws.com:30080/"
health_url         = null
idle_minutes       = 5
heartbeat_param    = "/neon-portfolio/last_heartbeat"
expose_sleep_route = false

# -------------------- Access configuration --------------------
admin_cidr     = ["0.0.0.0/0"]
use_ssm_deploy = false