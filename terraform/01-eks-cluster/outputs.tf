output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "The endpoint for the EKS cluster API. Required to configure kubectl."
}

output "eks" {
  value       = module.eks
  description = "The EKS module itself."
}

output "cluster_certificate_authority_data" {
  value       = module.eks.cluster_certificate_authority_data
  description = "The certificate authority data for the EKS cluster."
}

output "cluster_name" {
  value       = module.eks.cluster_name
  description = "The name of the EKS cluster."
}

output "region" {
  value       = local.region
  description = "The AWS region where the EKS cluster is deployed."
}

output "name" {
  value       = local.name
  description = "Cluster name."
}

output "aws_account" {
  description = "Aws account"
  value       = data.aws_caller_identity.current.account_id
}

output "access_entries" {
  value       = module.eks.access_entries
  description = "Security group entries that allow access to the EKS cluster."
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

