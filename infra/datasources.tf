############################################
# Discover EC2 instances by Name tag (any state)
############################################
data "aws_instances" "by_name_tag" {
  filter {
    name   = "tag:Name"
    values = [var.instance_name_tag]
  }

  filter {
    name   = "instance-state-name"
    values = ["pending", "running", "stopped", "stopping"]
  }
}

############################################
# Load detailed info for each candidate ID
# (state, launch_time, etc.) — keyed by instance_id
############################################
data "aws_instance" "candidates" {
  for_each    = toset(data.aws_instances.by_name_tag.ids)
  instance_id = each.value
}

############################################
# Latest Amazon Linux 2023 AMI (kernel 6.1, x86_64) via SSM public parameter
############################################
data "aws_ssm_parameter" "al2023_latest" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
