############################################
# TFLint configuration — helmkube-autowake
# Purpose: enable AWS ruleset for us-east-1 and sane defaults
############################################
plugin "aws" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"

  region = "us-east-1"
}

############################################
# Core TFLint behavior
# - module: follow modules (not критично, но полезно)
# - disabled_by_default: keep built-in rules ON
############################################
config {
  module              = true
  force               = false
  disabled_by_default = false
}
