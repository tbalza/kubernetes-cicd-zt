terraform {
  required_version = "1.7.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.59.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.0.4"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.37.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.2"
    }
  }
}

###############################################################################
# Providers
###############################################################################

# kubectl can wait till eks is ready, and then apply yaml
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

# kubernetes provider cannot wait until eks is provisioned before applying yaml
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                          # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name] # var.cluster_name
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint                                 # var.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data) # var.cluster_ca_cert
    exec {
      api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}