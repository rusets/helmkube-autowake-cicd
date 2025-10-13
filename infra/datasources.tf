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

locals {
  autodetected_ids         = try(data.aws_instances.by_name_tag.ids, [])
  autodetected_instance_id = length(local.autodetected_ids) > 0 ? local.autodetected_ids[0] : null
}