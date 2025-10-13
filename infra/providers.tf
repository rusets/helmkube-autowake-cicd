provider "aws" {
  region = var.region
}



provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

data "aws_caller_identity" "current" {}