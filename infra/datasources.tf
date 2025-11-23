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
# Pick the most recent instance with safe priority:
# running → pending → stopping → stopped
############################################
locals {
  by_state_running  = [for i in data.aws_instance.candidates : "${i.launch_time}|${i.id}" if i.instance_state == "running"]
  by_state_pending  = [for i in data.aws_instance.candidates : "${i.launch_time}|${i.id}" if i.instance_state == "pending"]
  by_state_stopping = [for i in data.aws_instance.candidates : "${i.launch_time}|${i.id}" if i.instance_state == "stopping"]
  by_state_stopped  = [for i in data.aws_instance.candidates : "${i.launch_time}|${i.id}" if i.instance_state == "stopped"]

  latest_running_id  = length(local.by_state_running) > 0 ? split("|", sort(local.by_state_running)[length(local.by_state_running) - 1])[1] : null
  latest_pending_id  = length(local.by_state_pending) > 0 ? split("|", sort(local.by_state_pending)[length(local.by_state_pending) - 1])[1] : null
  latest_stopping_id = length(local.by_state_stopping) > 0 ? split("|", sort(local.by_state_stopping)[length(local.by_state_stopping) - 1])[1] : null
  latest_stopped_id  = length(local.by_state_stopped) > 0 ? split("|", sort(local.by_state_stopped)[length(local.by_state_stopped) - 1])[1] : null

  autodetected_priority = compact([
    local.latest_running_id,
    local.latest_pending_id,
    local.latest_stopping_id,
    local.latest_stopped_id,
  ])
}

############################################
# Latest Amazon Linux 2023 AMI (kernel 6.1, x86_64) via SSM public parameter
############################################
data "aws_ssm_parameter" "al2023_latest" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
