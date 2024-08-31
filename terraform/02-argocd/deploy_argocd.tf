provider "aws" {
  region = data.terraform_remote_state.eks.outputs.region
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

###############################################################################
# Read state from eks cluster to extract outputs
###############################################################################

data "terraform_remote_state" "eks" {
  backend = "local" # Pending remote set up to enable collaboration, state locking etc.
  config = {
    path = "${path.module}/../01-eks-cluster/terraform.tfstate"
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
  name       = local.argocd_helm_chart.name        # "argo-cd"
  repository = local.argocd_helm_chart.repo        # "https://argoproj.github.io/argo-helm"
  chart      = local.argocd_helm_chart.releaseName # "argo-cd"
  version    = local.argocd_helm_chart.version     # "6.7.14" # pending reference this dynamically to argo-apps/argocd/config.yaml
  namespace  = local.argocd_helm_chart.namespace   # "argocd"

  #wait = false # might be needed!

  create_namespace = true
  values = [file("${path.module}/../../argo-apps/argocd/values.yaml")]

  set {                                                                            # used for ArgoCD Repo Server secrets. contains values that envsubst plugin uses (kustomize cannot load external env fed from tf by design, argocd cmp is a workaround)
    name  = "repoServer.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" # annotation to allows service account to assume aws role
    value = data.terraform_remote_state.eks.outputs.argo_cd_repo_iam_role_arn      # role/ArgoCDrepoRole
  }


  # patch the applicationset to delete all apps except argocd first, instead of deleting resources with kubectl
  # kubectl patch applicationset cluster-addons -n argocd --type=json -p='[{"op": "replace", "path": "/spec/generators/0/git/directories/0/path", "value": "argo-apps/argocd"}]'

  provisioner "local-exec" {
    when = destroy
        command = <<-EOT
          kubectl get crd -o name |
          grep -E 'argoproj.io|monitoring.coreos.com|fluent.io|elastic.co' |
          xargs -I {} kubectl patch {} -p '{"metadata":{"finalizers":[]}}' --type=merge &&
          kubectl -n argocd get app -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' |
          xargs -I {} kubectl delete all,pvc,secrets,configmaps,ingresses,networkpolicies,serviceaccounts,jobs,cronjobs,applicationsets --all -n {}
        EOT
  }
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

