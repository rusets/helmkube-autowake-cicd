############################################
# Lambda packaging — wake & sleep ZIP bundles
# Purpose: build local ZIP artifacts from Python sources on each apply
############################################

data "archive_file" "wake_instance" {
  type        = "zip"
  source_file = "${path.root}/../lambda/wake_instance.py"
  output_path = "${path.root}/../build/wake_instance.zip"
}

############################################
# Lambda packaging — sleep ZIP bundle
# Purpose: package autosleep Lambda from local Python source
############################################

data "archive_file" "sleep_instance" {
  type        = "zip"
  source_file = "${path.root}/../lambda/sleep_instance.py"
  output_path = "${path.root}/../build/sleep_instance.zip"
}
