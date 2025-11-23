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
# Latest Amazon Linux 2023 AMI (kernel 6.1, x86_64) via SSM public parameter
############################################
data "aws_ssm_parameter" "al2023_latest" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
