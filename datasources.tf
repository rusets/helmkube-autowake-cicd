# --- Discover EC2 instance by Name tag (safe for empty results) ---
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

# --- Safe locals (won't break on destroy) ---
locals {
  # [] if data-source is empty
  autodetected_ids         = try(data.aws_instances.by_name_tag.ids, [])
  # first id or null
  autodetected_instance_id = length(local.autodetected_ids) > 0 ? local.autodetected_ids[0] : null
  # final id or "MISSING" (single line to avoid HCL parse issues)
  instance_id_effective    = var.instance_id != null ? var.instance_id : (local.autodetected_instance_id != null ? local.autodetected_instance_id : "MISSING")
}
