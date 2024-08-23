provider "aws" {
  region = data.terraform_remote_state.eks.outputs.region
}

###############################################################################
# Read state from eks cluster to extract outputs
###############################################################################

data "terraform_remote_state" "eks" {
  backend = "local" # Pending remote set up to enable collaboration, state locking etc.
  config = {
    path = "${path.module}/../01-eks-cluster/terraform.tfstate"
  }
}

###############################################################################
# Providers
###############################################################################

provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                                                       # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name] # var.cluster_name
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
    exec {
      api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                                                       # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name] # var.cluster_name
    command     = "aws"
  }
}

################################################################################
# Argocd
################################################################################

# Dynamically load values from argocd's kustomization.yaml
locals {
  argocd_config = yamldecode(file("${path.module}/../../argo-apps/argocd/kustomization.yaml"))

  # IDE may show "unresolved reference" even though it's linked correctly in tf.
  argocd_helm_chart = local.argocd_config.helmCharts[0] # Access the first (or only) element in the list
}

resource "helm_release" "argo_cd" {

  # IDE may show "unresolved reference" even though it's linked correctly in tf.
  # referencing kustomization.yaml from argocd (inside /argo-apps/argocd)
  name       = local.argocd_helm_chart.name # "argo-cd"
  repository = local.argocd_helm_chart.repo # "https://argoproj.github.io/argo-helm"
  chart      = local.argocd_helm_chart.releaseName # "argo-cd"
  version    = local.argocd_helm_chart.version # "6.7.14" # pending reference this dynamically to argo-apps/argocd/config.yaml
  namespace = local.argocd_helm_chart.namespace # "argocd"

  #wait = false # might be needed!

  create_namespace = true
# "${tostring(data.terraform_remote_state.eks.outputs.ecr_repo_url)}"
  values = [file("${path.module}/../../argo-apps/argocd/values.yaml")]
#  values = [
#    file("../../${path.module}/argo-apps/argocd/values.yaml"),
#    <<-EOT
#    global:
#      env:
#        - name: ARGOCD_APP_DOMAIN2
#          value: "${data.terraform_remote_state.eks.outputs.argo_cd_aws_domain}"
#    EOT
#  ]

#  set { # used for ImageUpdater secrets. contains github credentials
#    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" # annotation to allows service account to assume aws role
#    value = data.terraform_remote_state.eks.outputs.argo_cd_image_iam_role_arn # role/ArgoCDRole
#  }

  set { # used for ArgoCD Repo Server secrets. contains values that envsubst plugin uses (kustomize cannot load external env fed from tf by design, argocd cmp is a workaround)
    name  = "repoServer.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" # annotation to allows service account to assume aws role
    value = data.terraform_remote_state.eks.outputs.argo_cd_repo_iam_role_arn # role/ArgoCDrepoRole
  }

  provisioner "local-exec" {
    when    = destroy
    #command = "kubectl get crd -o name | grep -E 'argoproj.io|monitoring.coreos.com|fluent.io|elastic.co' | xargs -I {} kubectl patch {} -p '{"metadata":{"finalizers":[]}}' --type=merge && kubectl -n argocd get app -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | xargs -I {} kubectl delete all,pvc,secrets,configmaps,ingresses,networkpolicies,serviceaccounts,jobs,cronjobs,applicationsets --all -n {}"
    command = <<-EOT
      kubectl get crd -o name |
      grep -E 'argoproj.io|monitoring.coreos.com|fluent.io|elastic.co' |
      xargs -I {} kubectl patch {} -p '{"metadata":{"finalizers":[]}}' --type=merge &&
      kubectl -n argocd get app -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' |
      xargs -I {} kubectl delete all,pvc,secrets,configmaps,ingresses,networkpolicies,serviceaccounts,jobs,cronjobs,applicationsets --all -n {}
    EOT
  }

  # delete all,pvc,secrets,configmaps,ingresses,networkpolicies,serviceaccounts,jobs,cronjobs,applicationsets

  # Ensure that the Kubernetes namespace exists before deploying
#  depends_on = [
#    #kubernetes_namespace.argo_cd,
#    #helm_release.cert_manager
#    #data.terraform_remote_state.eks.outputs.eks, # pending. wait until node groups are provisioned before deploying argocd
#    #data.terraform_remote_state.eks.outputs.eks_managed_node_groups # pending. wait until node groups are provisioned before deploying argocd
#  ]
}

## ArgoCD apply ApplicationSet
## Uses directory generator to dynamically create argo-apps in subdirectories
## Kustomize uses helmChart for 3rd party charts with local repo overrides (values.yaml) and load additional k8s manifests

resource "kubectl_manifest" "example_applicationset" {
  yaml_body = file("${path.module}/../../argo-apps/argocd/applicationset.yaml")

  depends_on = [
    helm_release.argo_cd # kubectl_manifest.kustomize_patch
  ]
}

## Create namespace
#resource "kubernetes_namespace" "argo_cd" {
#  metadata {
#    name = "argocd"
#  }
#}

# ArgoCD AWS Account

#resource "kubectl_manifest" "aws_account_configmap" { # global variables that come from tf make sense not to be committed to repo, to be consumed by kustomize itself, not pods, through argocd cmp
#  # pending. `terraform_remote_state` stuff will change when on the same tf (infra and argocd bootstrap should be spun/destroyed without scripts)
#  yaml_body = <<-YAML
#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: global-variables
#  namespace: argocd
#data:
#  ACCOUNT_ID: "${data.terraform_remote_state.eks.outputs.aws_account}"
#  CLUSTER_NAME: "${data.terraform_remote_state.eks.outputs.name}"
#  REGION: "${data.terraform_remote_state.eks.outputs.region}"
#  ECR_REPO: "${data.terraform_remote_state.eks.outputs.repository_url}"
#  DOMAIN: "${data.terraform_remote_state.eks.outputs.domain}"
#  YAML
#
#  depends_on = [
#    #helm_release.argo_cd
#  ]
#}


#output "account_id" {
#  description = "The AWS account ID."
#  value       = data.aws_caller_identity.current.account_id
#}

#resource "kubectl_manifest" "aws_account_secret" { # pending. change name to token for clarity
#  yaml_body = <<-YAML
#apiVersion: v1
#kind: Secret
#metadata:
#  name: aws-account
#  namespace: kube-system
#type: Opaque
#data:
#  aws-account: ${base64encode(data.aws_caller_identity.current.account_id)}
#  YAML
#
#  depends_on = [
#    #helm_release.aws_load_balancer_controller,
#    #module.eks
#  ]
#}


########################################################

### must be set before tf apply
## export TF_VAR_ARGOCD_GITHUB_TOKEN=123example
#
### Import environment variables as TF variable
#variable "ARGOCD_GITHUB_TOKEN" {
#  description = "API token for Cloudflare"
#  type        = string
#  sensitive   = true
#}


### Pass CF API token to k8s Secret
## kubectl create secret generic cloudflare-api-key --from-literal=apiKey=123example -n kube-system
#resource "kubectl_manifest" "cloudflare_api_key" { # pending. change name to token for clarity
#  yaml_body = <<-YAML
#apiVersion: v1
#kind: Secret
#metadata:
#  name: argocd-github-app-secret
#  namespace: argocd
#type: Opaque
#data:
#  apiToken: ${base64encode(var.ARGOCD_GITHUB_TOKEN)}
#  YAML
#
##  depends_on = [
##    #helm_release.aws_load_balancer_controller,
##    module.eks
##  ]
#}

########################################################

# print argocd password after tf apply
resource "null_resource" "get_argocd_admin_password" {
  # Triggers the provisioner when apply is called
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
      kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode
    EOT
  }

  depends_on = [
    helm_release.argo_cd
  ]

}

########################################################

# Fix interdependencies for graceful provisioning and teardown ### check

#Yes absolutely, using depends_on in an output is 100% valid
#and used for exactly this kind of timing issue where an output for a single resource isn't fully available
#until some other resource completes. S3 bucket and bucket policy is another common one. Or IAM role and role attachments.

#output "cluster_endpoint" {
#  description = "Endpoint for your Kubernetes API server"
#  value       = data.terraform_remote_state.eks.outputs.cluster_endpoint # try(module.eks.cluster_endpoint, null)
#
#  depends_on = [
#    data.terraform_remote_state.eks.outputs.access_entries,
#    data.terraform_remote_state.eks.outputs.access_policy_associations,
#  ]
#}
#
#output "cluster_certificate_authority_data" {
#  description = "Base64 encoded certificate data required to communicate with the cluster"
#  value       = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data # try(aws_eks_cluster.this[0].certificate_authority[0].data, null)
#
#  depends_on = [
#    data.terraform_remote_state.eks.outputs.access_entries,
#    data.terraform_remote_state.eks.outputs.access_policy_associations,
#  ]
#}

