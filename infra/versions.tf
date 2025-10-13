terraform {
  required_version = ">= 1.6"
  backend "s3" {}
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.60" }
    archive = { source = "hashicorp/archive", version = "~> 2.6" }
    null    = { source = "hashicorp/null", version = "~> 3.2" }
  }
}