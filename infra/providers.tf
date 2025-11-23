############################################
# Providers (inline kube creds — no config_path)
############################################

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.29.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.1"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

############################################
# AWS Provider (region via variable)
############################################
provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

############################################
# Kubeconfig path (embedded kubeconfig on disk)
############################################
variable "kubeconfig_path" {
  type    = string
  default = "../build/k3s-embed.yaml"
}

############################################
# Locals — decode kubeconfig once and reuse for providers
############################################
locals {
  kubeconfig_abs = abspath("${path.root}/../build/k3s-embed.yaml")
  kc             = yamldecode(file(local.kubeconfig_abs))

  _cluster = local.kc.clusters[0].cluster
  _user    = local.kc.users[0].user

  _api     = local._cluster.server
  _ca_pem  = base64decode(local._cluster["certificate-authority-data"])
  _crt_pem = base64decode(local._user["client-certificate-data"])
  _key_pem = base64decode(local._user["client-key-data"])
}

############################################
# Kubernetes Provider (inline certs/keys from kubeconfig)
############################################
provider "kubernetes" {
  host                   = local._api
  cluster_ca_certificate = local._ca_pem
  client_certificate     = local._crt_pem
  client_key             = local._key_pem
}

############################################
# Helm Provider (reuses the same inline client config)
############################################
provider "helm" {
  kubernetes = {
    host                   = local._api
    cluster_ca_certificate = local._ca_pem
    client_certificate     = local._crt_pem
    client_key             = local._key_pem
  }
}
