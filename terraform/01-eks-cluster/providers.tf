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

#data "aws_eks_cluster" "cluster" {
#  name = module.eks.cluster_name
#}
#
#data "aws_eks_cluster_auth" "cluster" {
#  name = module.eks.cluster_name
#}

#provider "kubernetes" {
#  config_path = "~/.kube/config"
#}
#provider "helm" {
#  kubernetes {
#    config_path = "~/.kube/config"
#  }
#}