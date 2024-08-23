provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# local helm v3.14.4
# local kubectl v1.29.3
# aws kubernetes v1.29

locals {
  name            = "django-production7" # cluster name
  cluster_version = "1.29"              # 1.29
  region          = "us-east-1"
  domain          = "tbalza.net"

  vpc_cidr = "10.0.0.0/16" # ~65k IPs
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  rds_user   = "django"
  rds_dbname = "postgres"
  rds_port   = 5432 # postgres default
  repo_url   = "https://github.com/tbalza/kubernetes-cicd-zt.git"

  # SSM Parameter values
  parameters = {

    # e.g. tbalza.net (used by ExternalDNS) (and argocd)
    "domain" = {
      value = local.domain
    }

    "elastic_api_password" = {
      value = random_password.elastic_password.result
    }

    "elastic_api_username" = {
      value = "elastic" # pending move to argo-apps/elastic/secrets.yaml as "merge" in ExternalSecret
    }

    "elastic_api_roles" = {
      value = "superuser" # pending move to argo-apps/elastic/secrets.yaml as "merge" in ExternalSecret
    }

    "django_debug" = {
      value = "FALSE"
    }

    "region" = {
      value = local.region
    }

    "account" = {
      value = data.aws_caller_identity.current.account_id
    }

    "cluster_name" = {
      value = local.name
    }

    # (used by Jenkins/Kaniko)
    "ecr_repo" = {
      value = module.ecr.repository_url
    }

    "ecr_repo_name" = {
      value = local.name # right now the name of the cluster is being used for the app name # pending
    }

    "ecr_region" = {
      value = local.region
    }

    "repo_url" = {
      value = local.repo_url # right now the name of the cluster is being used for the app name # pending
    }

    "jenkins_github_app_user" = {
      value = var.ARGOCD_GITHUB_USER # not yet setup since repo is public
    }

    "jenkins_github_app_token" = {
      value = var.ARGOCD_GITHUB_TOKEN # not yet setup since repo is public
    }

    # Django's params
    "rds_user" = {
      value = local.rds_user
    }

    "rds_dbname" = {
      value = local.rds_dbname
    }

    "rds_password" = {                                 # pending # make type secret after test
      value = random_password.database_password.result # pending. figure out how not to include in tf state
    }

    "rds_port" = {
      value = local.rds_port
    }

    "rds_endpoint" = {
      value = split(":", module.db.db_instance_endpoint)[0] # regular output includes `endpoint:port`, this filters out the port
    }

    "django_secretkey" = {
      value = random_password.django_secretkey.result
    }

    #ArgoCD Image Updater Github App Secret

    "argo_cd_github_app_user" = { # check
      value = var.ARGOCD_GITHUB_USER
    }

    "argo_cd_github_app_token" = { # check
      value = var.ARGOCD_GITHUB_TOKEN
    }

    ###################################################################################

    "argo_cd_aws_account_number" = { # check
      value = data.aws_caller_identity.current.account_id
    }

    "argo_cd_aws_cluster_name" = { # check
      value = local.name
    }

    "argo_cd_aws_ecr_repo" = {                         # check
      value = split("/", module.ecr.repository_url)[0] # retains only the ecr domain <ecr domain>/<repo name>
    }

    "argo_cd_aws_ecr_repo_name" = { # check
      value = module.ecr.repository_name
    }

    "argo_cd_aws_region" = { # check
      value = local.region
    }

    "argo_cd_aws_domain" = { # check
      value = local.domain
    }

    ##################################################################################

    # ServiceAccounts ARN
    "argo_cd_iam_role_arn" = {
      value = aws_iam_role.argocd_image_updater.arn
    }

    "argo_cd_repo_iam_role_arn" = {
      value = aws_iam_role.argocd_repo.arn
    }

    "jenkins_iam_role_arn" = {
      value = aws_iam_role.jenkins.arn
    }

    "prometheus_iam_role_arn" = {
      value = aws_iam_role.prometheus.arn
    }

    "external_secrets_iam_role_arn" = {
      value = aws_iam_role.external_secrets.arn
    }

    "django_iam_role_arn" = {
      value = aws_iam_role.django.arn
    }


  }

  # argocd "internal" secret, generated randomly and set by default, not related to login passwords, apparently can drift and break the install
  # kubectl create secret generic argocd-secret --from-literal=server.secretkey=$(openssl rand -base64 32) -n argocd --dry-run=client -o yaml --save-config | kubectl apply -f - secret/argocd-secret configured
  # might need to be randomly declaratively generated and defined in SSM

  tags = {
    Example = local.name
  }
}

## ArgoCD ImageUpdater Github App Token
## must be set before tf apply
# export TF_VAR_ARGOCD_GITHUB_TOKEN=123example
# or just use terraform.tfvars
## Import environment variables as TF variable
variable "ARGOCD_GITHUB_TOKEN" {
  description = "ArgoCD Image Updater Github Personal Token"
  type        = string
  sensitive   = true
}

variable "ARGOCD_GITHUB_USER" {
  description = "ArgoCD Image Updater Github username"
  type        = string
  sensitive   = true
}

output "domain" {
  value       = local.domain
  description = "The name of domain"
}

###############################################################################
# SSM Parameter
###############################################################################

# Store secrets as SSM Parameters, that will be used by Kustomize via External Secrets Operator to dynamically inject secrets into pods

module "ssm-parameter" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "1.1.1"

  for_each = local.parameters

  # IDE may show unresolved reference name, it's normal (commenting unused values breaks the module)
  name            = try(each.value.name, each.key)
  value           = try(each.value.value, null)
  values          = try(each.value.values, [])
  type            = try(each.value.type, null)
  secure_type     = try(each.value.secure_type, null)
  description     = try(each.value.description, null)
  tier            = try(each.value.tier, null)
  key_id          = try(each.value.key_id, null)
  allowed_pattern = try(each.value.allowed_pattern, null)
  data_type       = try(each.value.data_type, null)

  # use module wrapper for multiple environments dev/qa/prod etc.

  depends_on = [
    module.eks,
    #    module.db, # check dependency loop
    #    module.ecr,
  ]

}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.20.0" # 20.11.1 # 20.17.2 #

  cluster_name             = local.name
  cluster_version          = local.cluster_version
  cluster_ip_family        = "ipv4"
  iam_role_use_name_prefix = true
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  #control_plane_subnet_ids = module.vpc.intra_subnets
  # database subnet ids # check

  #create_delay_dependencies = [for group in module.eks.eks_managed_node_groups : group.node_group_arn] # check eks-blueprints-addons

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Control Plane Logging
  # logs cloudwatch
  #cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  #cloudwatch_log_group_retention_in_days = 1
  #cloudwatch_log_group_kms_key_id        = var.kms_key_arn
  create_cloudwatch_log_group = false
  cloudwatch_log_group_class  = "INFREQUENT_ACCESS"

  enable_irsa = true

  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  create_kms_key            = false
  cluster_encryption_config = {}

  cluster_addons = {
    coredns = {
      resolve_conflicts_on_update = "OVERWRITE" #nodeSelector: {}
      resolve_conflicts_on_create = "OVERWRITE"
      addon_version               = "v1.11.1-eksbuild.9"
    }
    kube-proxy = {
      resolve_conflicts_on_update = "OVERWRITE" #nodeSelector: {}
      resolve_conflicts_on_create = "OVERWRITE"
      addon_version               = "v1.29.3-eksbuild.2"
    }
    vpc-cni = {
      resolve_conflicts_on_update = "OVERWRITE" #nodeSelector: {}
      resolve_conflicts_on_create = "OVERWRITE"
      addon_version               = "v1.18.1-eksbuild.3"
      before_compute              = true # Attempts to create VPC CNI before the associated nodegroups, EC2 bootstrap may still be needed
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true" # Increase max pods per node, t3.medium from 17 to 110 pod limit
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    # pending `kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class: "false"`
    # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/charts/aws-ebs-csi-driver/values.yaml
    #nodeSelector: {}
    #deploymentAnnotations: {}
    aws-ebs-csi-driver = {
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"
      service_account_role_arn    = module.ebs_csi_driver_irsa.iam_role_arn
      addon_version               = "v1.30.0-eksbuild.1" # v1.6.2-eksbuild.0
      configuration_values = jsonencode({
        #        storageClasses = [
        #          {
        #            name = "gp2"
        #            annotations = {
        #              "storageclass.kubernetes.io/is-default-class" = "false"
        #            }
        #          }
        #        ]
        sidecars : { # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/issues/1447 # pending
          snapshotter : {
            forceEnable : false
          }
        }

      })
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"  # This is custom AMI, `enable_bootstrap_user_data` must be set to True (ami_id not ami_type)
    instance_types = ["t3.medium"] # "m6i.large", "m5.large", "m5n.large", "m5zn.large"
    #    attach_cluster_primary_security_group = true
    #    vpc_security_group_ids = [aws_security_group.additional] # Check
    #    iam_role_additional_policies = {
    #    additional     = aws_iam_policy.additional.arn
    #    }
  }

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
    egress_nodes_ephemeral_ports_tcp = { # Check
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  #node_security_group_enable_recommended_rules = false
  #create_node_security_group  = false
  #node_security_group_id      = aws_security_group.eks_tooling.id

  # Enable node to node communication
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols" # Check
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_self_all = { # already created by module
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }
    # Control plane to nodes
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {

    ci-cd = { # green #

      name = "ci-cd-node-group"

      subnet_ids = module.vpc.private_subnets

      ami_type = "AL2_x86_64" # AL2_ARM_64 for arm
      #ami_id                     = data.aws_ami.eks_default.image_id # check pin to specific version
      #enable_bootstrap_user_data = true # Must be set when using custom AMI i.e. AL2_x86_64, but only if you provide ami_id (not ami_type)

      min_size     = 1
      max_size     = 2
      desired_size = 1

      capacity_type = "SPOT" # "ON_DEMAND" # SPOT instances nodes are created in random AZs without balance

      #      bootstrap_extra_args       = "--kubelet-extra-args '--max-pods=50'"
      #
      #      pre_bootstrap_user_data = <<-EOT
      #        export USE_MAX_PODS=false
      #      EOT

      # Set max pods to 110 (hardcoded) --max-pods=${var.cluster_max_pods}

      #      pre_bootstrap_user_data = <<-EOT
      #        #!/bin/bash
      #        LINE_NUMBER=$(grep -n "KUBELET_EXTRA_ARGS=\$2" /etc/eks/bootstrap.sh | cut -f1 -d:)
      #        REPLACEMENT="\ \ \ \ \ \ KUBELET_EXTRA_ARGS=\$(echo \$2 | sed -s -E 's/--max-pods=[0-9]+/--max-pods=110/g')"
      #        sed -i '/KUBELET_EXTRA_ARGS=\$2/d' /etc/eks/bootstrap.sh
      #        sed -i "$${LINE_NUMBER}i $${REPLACEMENT}" /etc/eks/bootstrap.sh
      #      EOT

      # before_compute in vpc-cni addon, adds 30 second delay so kubelet can assume ENABLE_PREFIX_DELEGATION = "true", but doesn't work reliably
      # CNI may well be set, but kubelet_extra_args --max-pods may sometimes not
      # hence bootstrap might be recommendable as a fail safe

      # !!!!!!

      #      bootstrap_extra_args = <<-EOT
      #              "max-pods" = 109
      #            EOT

      # VPC CNI
      # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2551

      # For determining which app goes to what nodegroup
      # taints are not compatible with ebs csi driver out of the box
      #      taints = [{
      #        key    = "ci-cd"
      #        value  = "true"
      #        effect = "NO_SCHEDULE"
      #      }]
      labels = {
        role = "ci-cd" # used by k8s/argocd. node selection, scheduling, grouping, policy enforcement
      }

      #force_update_version = true
      instance_types = ["t3.xlarge"] # Overrides default instance defined above

      description = "CI-CD managed node group launch template"

      ebs_optimized           = true
      disable_api_termination = false
      enable_monitoring       = false # Check # cloudwatch

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 30
            volume_type = "gp3"
            #iops                  = 3000 # Pending. this is for provisioned IOPS, disabled for testing
            #throughput            = 150 # Pending. this is for provisioned IOPS, disabled for testing
            encrypted = false # Check
            #kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      create_iam_role          = true
      iam_role_name            = "ci-cd-managed-node-group-role"
      iam_role_use_name_prefix = false
      iam_role_description     = "ci-cd Managed node group role"
      iam_role_tags = {
        Purpose = "ci-cd-managed-node-group-role-tag"
      }
      iam_role_additional_policies = {
        # node wide policies
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Enable SSM
      }

      launch_template_tags = {
        # enable discovery of autoscaling groups by cluster-autoscaler
        "k8s.io/cluster-autoscaler/enabled" : true,
        "k8s.io/cluster-autoscaler/${local.name}" : "owned",
      }

      tags = {
        ExtraTag = "ci-cd-node" # used for cost allocation, resource mgmt, automation
      }
    }

    ###################################################################################################

    django = {

      name = "django-node-group"

      subnet_ids = module.vpc.private_subnets

      ami_type = "AL2_x86_64" # AL2_ARM_64 for arm

      min_size     = 1
      max_size     = 3
      desired_size = 1

      capacity_type = "SPOT"

      #      bootstrap_extra_args = <<-EOT
      #              "max-pods" = 109
      #            EOT

      # For determining which app goes to what nodegroup
      # taints are not compatible with ebs csi driver out of the box

      # pending . taints can be now set in kustomize
      #      taints = [{
      #        key    = "django"
      #        value  = "true"
      #        effect = "NO_SCHEDULE"
      #      }]
      labels = {
        role = "django" # used by k8s/argocd. node selection, scheduling, grouping, policy enforcement
      }

      #force_update_version = true
      instance_types = ["t3.medium"] # Overrides default instance defined above

      description = "Django managed node group launch template"

      ebs_optimized           = true
      disable_api_termination = false
      enable_monitoring       = false # Check cloudwatch
      #cloudwatch_log_group_class = "INFREQUENT_ACCESS" # Check cloudwatch

      block_device_mappings = {
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size = 30
            volume_type = "gp3" #gp3?
            encrypted   = false # Check
            #kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      create_iam_role          = true
      iam_role_name            = "django-managed-node-group-role"
      iam_role_use_name_prefix = false
      iam_role_description     = "django managed node group role"
      iam_role_tags = {
        Purpose = "django-managed-node-group-role-tag"
      }
      iam_role_additional_policies = {
        # node wide policies
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Enable SSM
      }

      launch_template_tags = {
        # enable discovery of autoscaling groups by cluster-autoscaler
        "k8s.io/cluster-autoscaler/enabled" : true,
        "k8s.io/cluster-autoscaler/${local.name}" : "owned",
      }

      tags = {
        ExtraTag = "django-node" # used for cost allocation, resource mgmt, automation
      }
    }

  }



  # check
  access_entries = {

    fluent-operator = {
      principal_arn     = aws_iam_role.fluent_operator.arn # aws_iam_role.fluent_operator.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    fluent-operator2 = {                                    # change for fluent-bit
      principal_arn     = aws_iam_role.fluent_operator2.arn # aws_iam_role.fluent_operator.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    eck-operator = { # change to eck-stack
      principal_arn     = aws_iam_role.elastic_operator.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    eck-operator2 = {
      principal_arn     = aws_iam_role.elastic_operator2.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    external-dns = {
      principal_arn     = aws_iam_role.external_dns.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }
    #
    #    cert-manager = {
    #      principal_arn     = aws_iam_role.cert_manager.arn
    #      kubernetes_groups = []
    #
    #      policy_associations = {
    #        admin_policy = {
    #          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
    #          access_scope = {
    #            type = "cluster" # check
    #          }
    #        }
    #      }
    #    }

    external-secrets = {
      principal_arn     = aws_iam_role.external_secrets.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }


    argocdrepo = {
      principal_arn     = aws_iam_role.argocd_repo.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    imageupdater = { # argocd image updater
      principal_arn     = aws_iam_role.argocd_image_updater.arn
      kubernetes_groups = []

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    jenkins = {
      principal_arn     = aws_iam_role.jenkins.arn
      kubernetes_groups = []

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    prometheus = {
      principal_arn     = aws_iam_role.prometheus.arn
      kubernetes_groups = []

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }

    django = {
      principal_arn     = aws_iam_role.django.arn
      kubernetes_groups = []

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # check
          access_scope = {
            type = "cluster" # check
          }
        }
      }
    }


  }
}

#resource "aws_iam_role" "this" {
#  for_each = toset(["argocd", "jenkins", "alertmanager", "kubestatemetrics", "nodexporter", "grafana", "prometheus", "prometheusoperator"])
#
#  name = each.key
#
#  assume_role_policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Action = "sts:AssumeRole"
#        Effect = "Allow"
#        Sid    = "Example"
#        Principal = {
#          Service = "ec2.amazonaws.com"
#        }
#      },
#    ]
#  })
#
#  tags = local.tags
#}

## STS

# pending check access entries
# pending implement workspaces
# pending implement remote state

# https://stackoverflow.com/questions/77439459/configure-iam-for-fluent-bit-on-aws-eks
# https://github.com/terraform-aws-modules/terraform-aws-iam/tree/master/examples/iam-role-for-service-accounts-eks

#module "fluentbit_irsa_role" {
#  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#  version = "5.11.1"
#
#  role_name = "fluent_operator" # "company-k8s-fluentbit-cloudwatch-irsa-role-${terraform.workspace}"
#
#  oidc_providers = {
#    main = {
#      provider_arn               = module.eks.oidc_provider_arn #data.terraform_remote_state.k8s-cluster.outputs.cluster_oidc_provider_arn
#      namespace_service_accounts = ["fluent:fluent-bit"] # ["${var.fluentbit_namespace}:${var.fluentbit_service_account_name}"]
#    }
#  }
#}
#
#module "fluentbit_irsa_role2" {
#  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#  version = "5.11.1"
#
#  role_name = "fluent_operator2" # "company-k8s-fluentbit-cloudwatch-irsa-role-${terraform.workspace}"
#
#  oidc_providers = {
#    main = {
#      provider_arn               = module.eks.oidc_provider_arn #data.terraform_remote_state.k8s-cluster.outputs.cluster_oidc_provider_arn
#      namespace_service_accounts = ["fluent:fluent-operator"] # ["${var.fluentbit_namespace}:${var.fluentbit_service_account_name}"]
#    }
#  }
#}

#resource "aws_iam_policy" "fluent_logs_policy" {
#  name = "fluentbit-policy"
#
#  description = "Role use to create logs from K8S to elasticsearch"
#
#  policy = jsonencode({
#    Version = "2012-10-17",
#    Statement = [
#      {
#        Action = [
#          "ec2:DescribeTags",
#          "logs:PutLogEvents",
#          #"cloudwatch:PutMetricData",
#          "logs:DescribeLogStreams",
#          "logs:DescribeLogGroups",
#          "logs:CreateLogStream",
#          "logs:CreateLogGroup"
#        ],
#        Effect   = "Allow",
#        Resource = "*"
#      }
#    ]
#  })
#}
#
#resource "aws_iam_policy_attachment" "attach_fluent_logs_policy" {
#  name       = "attach-fluent-logs-policy"
#  policy_arn = aws_iam_policy.fluent_logs_policy.arn
#  roles      = [module.fluentbit_irsa_role.iam_role_name]
#}

#############
# fluent

resource "aws_iam_role" "fluent_operator" {
  name = "FluentRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:fluent:fluent-operator" # "namespace:service-account-name"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "fluent_operator2" {
  name = "FluentRole2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:fluent:fluent-bit" # "namespace:service-account-name"
          }
        }
      },
    ]
  })
}

##############

resource "aws_iam_role" "elastic_operator" {
  name = "ElasticRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:eck-stack:eck-pass" # "namespace:service-account-name"
          }
        }
      },
    ]
  })
}


resource "aws_iam_role" "elastic_operator2" {
  name = "ElasticRole2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:elastic:elastic-operator" # "namespace:service-account-name"
          }
        }
      },
    ]
  })
}

##########

resource "aws_iam_role" "argocd_repo" {
  name = "ArgoCDrepoRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:argocd:argo-cd-argocd-repo-server" # "namespace:service-account-name"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "argocd_image_updater" {
  name = "ImageUpdaterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:argocd:argocd-image-updater" #"namespace:service-account-name"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "jenkins" {
  name = "JenkinsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:jenkins:jenkins" #"namespace:service-account-name"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "django" {
  name = "DjangoRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "eks.amazonaws.com"
        },
      },
      # External Secrets Operator reqs (jwt auth)
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:django:django" #"namespace:service-account-name"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "prometheus" {
  name = "PrometheusRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role" "external_secrets" { # check
  name = "ExternalSecretsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

output "argo_cd_imageupdater_iam_role_arn" {
  value = aws_iam_role.argocd_image_updater.arn
}

output "argo_cd_aws_domain" {
  value = local.domain
}

output "ecr_repo_url" {
  value = split("/", module.ecr.repository_url)[0]
}

output "argo_cd_repo_iam_role_arn" {
  value = aws_iam_role.argocd_repo.arn
}

output "jenkins_iam_role_arn" {
  value = aws_iam_role.jenkins.arn
}

output "prometheus_iam_role_arn" {
  value = aws_iam_role.prometheus.arn
}

output "external_secrets_iam_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "django_iam_role_arn" {
  value = aws_iam_role.django.arn
}

#output "image_updater_role_arn" {
#  value = aws_iam_role.argocd_image_updater.arn
#}

## Allow Jenkins to push images to ECR
#resource "aws_iam_policy" "jenkins_ecr_policy" {
#  name        = "JenkinsECRAccessPolicy"
#  path        = "/"
#  description = "Allows Jenkins to push images to ECR"
#
#  policy = <<EOF
#{
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ecr:GetAuthorizationToken",
#                "ecr:BatchCheckLayerAvailability",
#                "ecr:InitiateLayerUpload",
#                "ecr:UploadLayerPart",
#                "ecr:CompleteLayerUpload",
#                "ecr:PutImage"
#            ],
#            "Resource": "*"
#        }
#    ]
#}
#EOF
#}
#
## Attach Jenkins ECR policy to role
#resource "aws_iam_role_policy_attachment" "jenkins_ecr_policy_attachment" {
#  role       = aws_iam_role.jenkins.name
#  policy_arn = aws_iam_policy.jenkins_ecr_policy.arn
#}


################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.9.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]      # ~4k IPs
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)] # ~256 IPs
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)] # ~256 IPs

  #intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)] # used for control_plane_subnet_ids cluster (?)

  create_database_subnet_group = true

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true # needed for EFS
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1 # required for load balancer controller
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1 # required for load balancer controller
  }

  tags = local.tags
}

module "ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "3.1.0"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn # Check
  ]

  key_service_roles_for_autoscaling = [
    # required for the ASG to manage encrypted volumes for nodes
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling", # Check
    # required for the cluster / persistentvolume-controller to create encrypted PVCs
    module.eks.cluster_iam_role_arn,
  ]

  # Aliases
  aliases = ["eks/${local.name}/ebs"]

  tags = local.tags
}

################################################################################
# Permissions
################################################################################
## https://www.youtube.com/watch?v=kRKmcYC71J4
## Role for other user/team members to assume. get access to cluster
#module "allow_eks_access_iam_policy" {
#  source        = "terraform-aws-modules/iam/aws//modules/iam-policy"
#  version       = "5.3.1"
#  name          = "allow-eks-access"
#  create_policy = true
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Action = [
#          "eks:DescribeCluster",
#        ]
#        Effect   = "ALLow"
#        Resource = "*"
#      },
#    ]
#  })
#}
#
## Role for other user/team members to assume. get access to cluster
#module "eks_admins_iam_role" {
#  source                  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
#  version                 = "5.3.1"
#  role_name               = "eks-admin" # full access to kubernetes API
#  create_role             = true
#  role_requires_mfa       = false
#  custom_role_policy_arns = [module.allow_eks_access_iam_policy.arn] # attach policy above
#  trusted_role_arns = [
#    "arn:aws:iam::${module.vpc.vpc_owner_id}:root" # allow any user in account to assume role
#  ]
#}
#
## Create users
#module "user1_iam_user" {
#  source                        = "terraform-aws-modules/iam/aws//modules/iam-user"
#  version                       = "5.3.1"
#  name                          = "user1"
#  create_iam_access_key         = false
#  create_iam_user_login_profile = false
#  force_destroy                 = true
#}
#
## Allow assume
#module "allow_assume_eks_admin_iam_policy" {
#  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
#  version = "5.3.1"
#  name    = "allow-assume-eks-admin-iam-role"
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Action = [
#          "sts:AssumeRole",
#        ]
#        Effect   = "ALLow"
#        Resource = module.eks_admins_iam_role.iam_role_arn
#      },
#    ]
#  })
#}
#
## Create group, add user to group
#module "eks_admins_iam_group" {
#  source                            = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
#  version                           = "5.3.1"
#  name                              = "eks-admin"
#  attach_iam_self_management_policy = false
#  create_group                      = true
#  group_users                       = [module.user1_iam_user.iam_user_name]
#  custom_group_policy_arns          = [module.allow_assume_eks_admin_iam_policy.arn]
#}

# Node SG
resource "aws_security_group" "remote_access" {
  name_prefix = "${local.name}-remote-access"
  description = "Allow remote SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "argo_cd access"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "argo_cd access HTTPS"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-remote" })
}

resource "aws_iam_policy" "node_additional" {
  name        = "${local.name}-additional"
  description = "Example usage of node additional policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:*", # "ec2:Describe*" # check
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = local.tags
}

data "aws_ami" "eks_default" { # Retrieve the latest EKS optimized AMI
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${local.cluster_version}-v*"]
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
  #load_config_file = false
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
  #load_config_file = false
}

#data "aws_eks_cluster" "cluster" {
#  name = module.eks.cluster_name
#}
#
#data "aws_eks_cluster_auth" "cluster" {
#  name = module.eks.cluster_name
#}

###############################################################################
# Load balancer
###############################################################################

# by default ALB creates one per ingress, to combine use annotation
# alb.ingress.kubernetes.io/group.name: django-production

module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.41.0"

  role_name                              = "aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    sts = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

#resource "aws_iam_role_policy_attachment" "alb_controller_policy_attachment" {
#  role       = module.aws_load_balancer_controller_irsa_role.iam_role_name
#  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
#}

# Load balancer controller uses tags to discover subnets in which it can in which in can create load balancers
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1" # (Chart 1.8.1, LBC 2.8.1) ####### (Chart 1.7.2, LBC 2.7.2) requires Kubernetes 1.22+

  set {
    name  = "replicaCount" # by default it creates 2 replicas
    value = 1
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" # annotation to allows service account to assume aws role
    value = module.aws_load_balancer_controller_irsa_role.iam_role_arn
  }

  values = [
    <<-EOF
    nodeSelector:
      role: "ci-cd"
    EOF
  ]

  depends_on = [
    module.aws_load_balancer_controller_irsa_role,
    module.eks # important
  ]
}

################################################################################
# EBS CSI Driver
################################################################################

# Create iam role for service account for the block device
# IAM additional policy https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2826 # check
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.41.0"

  # create_role      = false
  role_name_prefix = "${module.eks.cluster_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Enable gp3 for aws-ebs-csi-driver
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"

    annotations = {
      # Annotation to set gp3 as default storage class
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    encrypted = false # check
    fsType    = "ext4"
    type      = "gp3"
  }

  depends_on = [
    module.eks
  ]
}

# Disable GP2 as default to prevent conflicts
# kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Forbidden: updates to provisioner are forbidden., volumeBindingMode: Invalid value: "Immediate": field is immutable

#resource "kubectl_manifest" "update_gp2_storage_class" {
#  yaml_body = <<-YAML
#apiVersion: storage.k8s.io/v1
#kind: StorageClass
#metadata:
#  name: gp2
#  annotations:
#    storageclass.kubernetes.io/is-default-class: "false"
#YAML
#
#  depends_on = [
#    module.eks
#  ]
#}

# Pending on a cleaner way to do this within the EKS module, or tf resource
resource "null_resource" "update_gp2" {
  triggers = {
    cluster_name     = module.eks.cluster_name
    cluster_endpoint = module.eks.cluster_endpoint
  }
  provisioner "local-exec" {
    command = "kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class=false --overwrite"
  }
  depends_on = [
    null_resource.update_kubeconfig
  ]
}


###############################################################################
# ECR
###############################################################################

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "2.2.1"

  repository_name = local.name

  repository_read_write_access_arns = [aws_iam_role.jenkins.arn] # pending . not attaching policy # depends on not set!!! arns could be list, # pending
  create_lifecycle_policy           = true
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  repository_force_delete = true

  tags = local.tags

  depends_on = [
    module.eks,
  ]

}

# Jenkins is going to push images to ECR
resource "aws_iam_policy" "jenkins_ecr" {
  name        = "jenkinsECRPolicy"
  path        = "/"
  description = "Allows Jenkins to push and pull images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_attach" {
  role       = aws_iam_role.jenkins.name # Assumes `aws_iam_role.jenkins` is defined elsewhere in your Terraform code
  policy_arn = aws_iam_policy.jenkins_ecr.arn
}

#####
#resource "aws_iam_policy" "django_ecr" { # check AmazonEC2ContainerRegistryPowerUser
#  name        = "DjangoECRPolicy"
#  path        = "/"
#  description = "Allows Django to list ECR artifacts" # pending
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Effect = "Allow"
#        Action = [
#          "ecr:GetAuthorizationToken",       # req
#          "ecr:BatchCheckLayerAvailability", # req
#          "ecr:GetDownloadUrlForLayer",      # req
#          "ecr:GetRepositoryPolicy",
#          "ecr:DescribeRepositories",
#          "ecr:ListImages",
#          "ecr:DescribeImages",
#          "ecr:BatchGetImage", # req
#          "ecr:InitiateLayerUpload",
#          "ecr:UploadLayerPart",
#          "ecr:CompleteLayerUpload",
#          "ecr:PutImage",
#          "ecr:*",
#          # https://github.com/argoproj/argo-cd/issues/8097
#        ]
#        Resource = "*"
#      },
#    ]
#  })
#}
#
#resource "aws_iam_role_policy_attachment" "django_ecr_attach" {
#  role       = aws_iam_role.django.name
#  policy_arn = aws_iam_policy.django_ecr.arn
#}

#####

#resource "aws_iam_policy" "argocd_ecr" { # check AmazonEC2ContainerRegistryPowerUser
#  name        = "ArgoCDECRPolicy"
#  path        = "/"
#  description = "Allows argoCD to list ECR artifacts" # pending
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Effect = "Allow"
#        Action = [
#          "ecr:GetAuthorizationToken",       # req
#          "ecr:BatchCheckLayerAvailability", # req
#          "ecr:GetDownloadUrlForLayer",      # req
#          "ecr:GetRepositoryPolicy",
#          "ecr:DescribeRepositories",
#          "ecr:ListImages",
#          "ecr:DescribeImages",
#          "ecr:BatchGetImage", # req
#          "ecr:InitiateLayerUpload",
#          "ecr:UploadLayerPart",
#          "ecr:CompleteLayerUpload",
#          "ecr:PutImage",
#          # https://github.com/argoproj/argo-cd/issues/8097
#        ]
#        Resource = "*"
#      },
#    ]
#  })
#}
#
#resource "aws_iam_role_policy_attachment" "argocd_ecr_attach" {
#  role       = aws_iam_role.argocd_image_updater
#  policy_arn = aws_iam_policy.argocd_ecr.arn
#}



# ArgoCD Image Updater is going to read ECR
resource "aws_iam_policy" "imageupdater_ecr" { # check AmazonEC2ContainerRegistryPowerUser
  name        = "ImageUpdaterECRpolicy"
  path        = "/"
  description = "Allows argoCD to list ECR artifacts" # pending

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",       # req
          "ecr:BatchCheckLayerAvailability", # req
          "ecr:GetDownloadUrlForLayer",      # req
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage", # req
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:*",
          # https://github.com/argoproj/argo-cd/issues/8097
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "imageupdater_ecr_attach" {
  role       = aws_iam_role.argocd_image_updater.name
  policy_arn = aws_iam_policy.imageupdater_ecr.arn
}



output "repository_name" {
  description = "Name of the repository"
  value       = module.ecr.repository_name
}

output "repository_arn" {
  description = "Full ARN of the repository"
  value       = module.ecr.repository_arn
}

output "repository_registry_id" {
  description = "The registry ID where the repository was created"
  value       = module.ecr.repository_registry_id
}

output "repository_url" {
  description = "The URL of the repository (in the form `aws_account_id.dkr.ecr.region.amazonaws.com/repositoryName`)"
  value       = module.ecr.repository_url
}


###############################################################################
# External Secrets Operator
###############################################################################

# external secret management system with a KMS plugin to encrypt Secrets stored in etcd # pending

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "kube-system" # check
  version    = "0.9.18"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  #If set external secrets are only reconciled in the provided namespace # pending
  #  set {
  #    name  = "scopedNamespace"
  #    value = #?
  #  }

  values = [
    <<-EOF
    global:
      nodeSelector:
        role: "ci-cd"
    serviceAccount:
      create: true
      name: "external-secrets"
    EOF
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    module.eks # important
  ]
}

# Fluent operator
resource "aws_iam_policy" "fluent_ssm_read" { # check
  name = "SSM-for-fluent"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fluent_read_attach" { # check
  role       = aws_iam_role.fluent_operator.name
  policy_arn = aws_iam_policy.fluent_ssm_read.arn
}

# Fluent bit
resource "aws_iam_policy" "fluent2_ssm_read" { # check
  name = "SSM-for-fluent2"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fluent_read2_attach" { # check
  role       = aws_iam_role.fluent_operator2.name
  policy_arn = aws_iam_policy.fluent2_ssm_read.arn
}

# Elastic eck-pass
resource "aws_iam_policy" "elastic_ssm_read" { # check
  name = "SSM-for-elastic"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "elastic_read_attach" { # check
  role       = aws_iam_role.elastic_operator.name
  policy_arn = aws_iam_policy.elastic_ssm_read.arn
}

# Jenkins
resource "aws_iam_policy" "jenkins_ssm_read" { # check
  name = "SSM-for-jenkins"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_read_attach" { # check
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins_ssm_read.arn
}

# Django
resource "aws_iam_policy" "django_ssm_read" { # check
  name = "SSM-for-django"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "django_read_attach" { # check
  role       = aws_iam_role.django.name
  policy_arn = aws_iam_policy.django_ssm_read.arn
}

# ArgoCD Image Updater
resource "aws_iam_policy" "imageupdater_ssm_read" { # check
  name = "SSM-for-argocd-imageupdater"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "imageupdater_read_attach" { # check
  role       = aws_iam_role.argocd_image_updater.name
  policy_arn = aws_iam_policy.imageupdater_ssm_read.arn
}

# ArgoCD Repo
resource "aws_iam_policy" "argocd_repo_ssm_read" { # check
  name = "SSM-for-argocd-repo"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      "Action" : [
        "ssm:GetParameter*",
        "ssm:ListTagsForResource", # check
        "ssm:DescribeParameters"   # check
      ],
      Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*" # check .limit scope accordingly. SSM is region specific
    }]
  })
}

resource "aws_iam_role_policy_attachment" "reposerver_read_attach" { # check
  role       = aws_iam_role.argocd_repo.name
  policy_arn = aws_iam_policy.argocd_repo_ssm_read.arn
}


####### check

#resource "aws_iam_policy" "jenkins_admin" {
#  name   = "JenkinsAdminPolicy"
#  policy = jsonencode({
#    Version = "2012-10-17",
#    Statement = [
#      {
#        Effect   = "Allow",
#        Action   = "*",
#        Resource = "*"
#      }
#    ]
#  })
#}
#
#resource "aws_iam_role_policy_attachment" "jenkins_admin_attach" {
#  role       = aws_iam_role.jenkins.name
#  policy_arn = aws_iam_policy.jenkins_admin.arn
#}


###############################################################################
# TF Helpers
###############################################################################

## Update kubeconfig cluster name and region
resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_name     = module.eks.cluster_name
    cluster_endpoint = module.eks.cluster_endpoint
  }
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${local.name} --region ${local.region}"
  }
  depends_on = [
    module.eks
  ]
}

###############################################################################
# ExternalDNS
###############################################################################

## must be set before tf apply
# export TF_VAR_CFL_API_TOKEN=123example
# When using API Token authentication, the token should be granted Zone Read, DNS Edit privileges, and access to All zones

# optional: limit which Ingress objects are used as an ExternalDNS source via the ingress-class

## Import environment variables as TF variable
variable "CFL_API_TOKEN" {
  description = "API token for Cloudflare"
  type        = string
  sensitive   = true
}

## Pass CF API token to k8s Secret
# kubectl create secret generic cloudflare-api-key --from-literal=apiKey=123example -n kube-system
resource "kubectl_manifest" "cloudflare_api_key" { # pending. change name to token for clarity
  yaml_body = <<-YAML
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: kube-system
type: Opaque
data:
  apiToken: ${base64encode(var.CFL_API_TOKEN)}
  YAML

  depends_on = [
    #helm_release.aws_load_balancer_controller,
    module.eks
  ]
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  chart      = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  namespace  = "kube-system"
  version    = "1.14.5" # Chart 1.14.5, App 0.14.2

  values = [
    <<-EOF
    nodeSelector:
      role: "ci-cd"

    env:
    - name: CF_API_TOKEN
      valueFrom:
        secretKeyRef:
          name: cloudflare-api-token
          key: apiToken
    EOF
  ]

  #  set {
  #    name  = "extraArgs[0]" # API rate limit optimization
  #    value = "--cloudflare-dns-records-per-page=5000"
  #  }

  set {
    name  = "extraArgs[0]"
    value = "--source=ingress" # required for ALB
  }

  set {
    name  = "domainFilters[0]"
    value = local.domain # Necessary for helm install to succeed
  }

  set {
    name  = "provider.name"
    value = "cloudflare"
  }

  set {
    name  = "policy"
    value = "sync" # sync also deletes records. # upsert-only
  }

  set {
    name  = "txtOwnerId"
    value = local.name # cluster name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }

  set {
    name  = "serviceAccount.automountServiceAccountToken" # check
    value = true
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  depends_on = [
    kubectl_manifest.cloudflare_api_key
    #helm_release.aws_load_balancer_controller,
    #module.eks
  ]

}

resource "aws_iam_role" "external_dns" {
  name = "external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

################################################################################
## Cert-Manager
################################################################################
# This can only be used with NLB currently, as AWS LBC only supports ACM certs. There is a feature request pending, so ALB use might be enabled soon.
## DNS01 validation was used since it's needed when CI/CD apps are not publicly accessible
#
##resource "kubernetes_namespace" "cert_manager" {
##  metadata {
##    name = "cert-manager"
##  }
##}
#
#resource "kubectl_manifest" "cert_manager" {
#  yaml_body = file("../../${path.module}/argo-apps/argocd/cert-manager.yaml")
#
#  depends_on = [
#    helm_release.cert_manager
#  ]
#}
#
#resource "helm_release" "cert_manager" {
#  name       = "cert-manager"
#  chart      = "cert-manager"
#  repository = "https://charts.jetstack.io"
#  namespace  = "cert-manager" #
#
#  #create_namespace = true
#
#  version    = "1.14.5"
#
#  values = [
#    <<-EOF
#    nodeSelector:
#      role: "ci-cd"
#
#    EOF
#  ]
#
#  set {
#    name  = "installCRDs" # although deprecated, install fails with only crds.enabled=true, both crds.enabled and crds.keep are needed
#    value = "true"
#  }
#
##  set {
##    name  = "crds.enabled" # decides if the CRDs should be installed
##    value = "true"
##  }
##  set {
##    name  = "crds.keep" # prevent Helm from uninstalling the CRD when the Helm release is uninstalled
##    value = "true"
##  }
#
#  set {
#    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#    value = aws_iam_role.cert_manager.arn
#  }
#
#  set {
#    name  = "serviceAccount.name"
#    value = "cert-manager"
#  }
#
#  #         extraArgs:
#  #          - --logging-format=json
#  #        webhook:
#  #          extraArgs:
#  #            - --logging-format=json
#  #        cainjector:
#  #          extraArgs:
#  #            - --logging-format=json
#
#
#  depends_on = [
#    helm_release.aws_load_balancer_controller,
#    module.eks
#  ]
#
#}
#
#resource "aws_iam_role" "cert_manager" {
#  name = "cert-manager"
#
#  assume_role_policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Effect = "Allow"
#        Principal = {
#          Service = "eks.amazonaws.com"
#        }
#        Action = "sts:AssumeRole"
#      },
#    ]
#  })
#}

###############################################################################
# ACM
###############################################################################
# Load Balancer Controller only works with ACM certificates (and cert-manager can't issue ACM certs)
# added in release v2.8.0
# Support set the certificateArn for Ingress at the IngressClass level. This feature adds new certificateArn to the IngressClassParams Spec to configure the ARN of the certificates for all Ingresses that belong to IngressClass with this IngressClassParams.
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/guide/ingress/cert_discovery/

resource "kubectl_manifest" "ingress_class_params" { # check # pending
  yaml_body = <<-EOT
  apiVersion: elbv2.k8s.aws/v1beta1
  kind: IngressClassParams
  metadata:
    name: alb  # Ensure this matches the existing IngressClassParams name
  spec:
    certificateArn:
      - "${module.acm.acm_certificate_arn}"
  EOT

  depends_on = [
    helm_release.aws_load_balancer_controller, # check
    module.acm                                 # check
  ]
}

## must be set before tf apply
# export TF_VAR_CFL_ZONE_ID=123example

## Import environment variables as TF variable
variable "CFL_ZONE_ID" {
  description = "Zone ID for Cloudflare"
  type        = string
  sensitive   = true
}

# Create ACM wildcard cert, with DNS validation using Cloudflare
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "5.0.1"

  # ACM cert for subdomains only
  domain_name = "*.${local.domain}" # only for subdomains of *.tbalza.net, TLD is not included by default
  zone_id     = var.CFL_ZONE_ID

  validation_method = "DNS"

  validation_record_fqdns = cloudflare_record.validation[*].hostname

  wait_for_validation    = true
  create_route53_records = false

  #  subject_alternative_names = [
  #    "*.${local.domain}", # domain name and subject alternative name should not be repeated
  #  ]

  tags = {
    Name = local.domain
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
  ]

}

output "distinct_domain_names" {
  description = "List of distinct domains names used for the validation."
  value       = module.acm.distinct_domain_names
}

output "validation_domains" {
  description = "List of distinct domain validation options. This is useful if subject alternative names contain wildcards."
  value       = module.acm.validation_domains
}

###############################################################################
# Cloudflare
###############################################################################
# This block only takes care of validating the wildcard ACM cert.
# individual app CNAME entries are created dynamically by ExternalDNS (defined in the ingress of each app)

## must be set before tf apply
# export TF_VAR_CFL_API_TOKEN=123example

provider "cloudflare" {
  api_token = var.CFL_API_TOKEN
}

# Validate generated ACM cert by creating validation domain record
resource "cloudflare_record" "validation" {
  count = length(module.acm.distinct_domain_names)

  zone_id = var.CFL_ZONE_ID
  name    = element(module.acm.validation_domains, count.index)["resource_record_name"]
  type    = element(module.acm.validation_domains, count.index)["resource_record_type"]
  value   = trimsuffix(element(module.acm.validation_domains, count.index)["resource_record_value"], ".") # ensure no trailing periods that could disrupt DNS record creation
  ttl     = 60
  proxied = false

  allow_overwrite = true

  depends_on = [
    helm_release.aws_load_balancer_controller,
  ]

}

###############################################################################
# RDS - django-app
###############################################################################

# Pending. connection pooling (possibly using something like django-db-connection-pool or other external tools like PgBouncer).


# Create rds random password.
resource "random_password" "database_password" {
  length           = 28
  special          = true
  override_special = "!#$%&'()+,-.=?^_~" # special character whitelist
}

resource "random_password" "django_secretkey" {
  length      = 28
  special     = false
  min_numeric = 10
  #override_special = "!#$%&'()+,-.=?^_~" # special character whitelist
}

#############

### must be set before tf apply
## export TF_VAR_RDS_PASSWORD=123example
## optional: limit which Ingress objects are used as an ExternalDNS source via the ingress-class
### Import environment variables as TF variable
#variable "RDS_PASSWORD" {
#  description = "Django RDS db password"
#  type        = string
#  sensitive   = true
#}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.7.0"

  identifier = local.name

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  # aws rds describe-db-engine-versions --default-only --engine postgres
  engine               = "postgres"
  engine_version       = "16.2"
  family               = "postgres16" # DB parameter group
  major_engine_version = "16"         # DB option group
  instance_class       = "db.t4g.micro"

  #kms_key_id        = "arn:aws:kms:${var.aws_region}:${var.account_id}:key/${data.aws_ssm_parameter.kms_keyid.value}"

  allocated_storage     = 5
  max_allocated_storage = 10

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = local.rds_dbname
  username = local.rds_user
  port     = local.rds_port

  # Setting manage_master_user_password_rotation to false after it
  # has previously been set to true disables automatic rotation
  # however using an initial value of false (default) does not disable
  # automatic rotation and rotation will be handled by RDS.
  # manage_master_user_password_rotation allows users to configure
  # a non-default schedule and is not meant to disable rotation
  # when initially creating / enabling the password management feature
  manage_master_user_password_rotation              = false
  master_user_password_rotate_immediately           = false
  master_user_password_rotation_schedule_expression = "rate(60 days)"
  manage_master_user_password                       = false # Set to true to allow RDS to manage the master user password in Secrets Manager
  ##create_random_password                            = false # required if you supply your own password (i.e. SSM parameter) ## doesn't exist?


  password = random_password.database_password.result
  #password = aws_ssm_parameter.rds_password.value # random_password.database_password.result # data.aws_ssm_parameter.kms_keyid.value
  # IRSA + IAM DB auth?

  iam_database_authentication_enabled = false # pending
  publicly_accessible                 = false

  multi_az = false # false
  #availability_zone = local.azs
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

  create_db_option_group    = false # Use a default option group provided by AWS
  create_db_parameter_group = false # Use a default parameter group provided by AWS

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = false # check

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled          = false # check cloudwatch
  performance_insights_retention_period = 7
  create_monitoring_role                = false
  monitoring_interval                   = 0 # 0 disables collecting enhanced metrics
  monitoring_role_name                  = "example-monitoring-role-name"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Description for monitoring role"

  parameters = [ # pending. force SSL?
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = local.tags
  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }

  depends_on = [
    module.eks,
    #helm_release.aws_load_balancer_controller,
  ]

}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name        = local.name
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432 # pending local.rds_port
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = module.db.db_instance_address
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = module.db.db_instance_arn
}

output "db_instance_availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = module.db.db_instance_availability_zone
}

output "db_instance_endpoint" {
  description = "The connection endpoint"
  value       = split(":", module.db.db_instance_endpoint)[0] # regular output includes `endpoint:port`, this filters out the port
}

output "db_instance_engine" {
  description = "The database engine"
  value       = module.db.db_instance_engine
}

output "db_instance_engine_version_actual" {
  description = "The running version of the database"
  value       = module.db.db_instance_engine_version_actual
}

output "db_instance_hosted_zone_id" {
  description = "The canonical hosted zone ID of the DB instance (to be used in a Route 53 Alias record)"
  value       = module.db.db_instance_hosted_zone_id
}

output "db_instance_identifier" {
  description = "The RDS instance identifier"
  value       = module.db.db_instance_identifier
}

output "db_instance_resource_id" {
  description = "The RDS Resource ID of this instance"
  value       = module.db.db_instance_resource_id
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = module.db.db_instance_status
}

output "db_instance_name" {
  description = "The database name"
  value       = module.db.db_instance_name
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = module.db.db_instance_username
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = module.db.db_instance_port
}

#### Create namespace
#resource "kubernetes_namespace" "global_vars" {
#  metadata {
#    name = "globalvars"
#  }
#
#  depends_on = [
#    #helm_release.argo_cd
#    module.eks
#  ]
#
#}
#
#### pending. `terraform_remote_state` stuff will change when on the same tf (infra and argocd bootstrap should be spun/destroyed without scripts)
#resource "kubectl_manifest" "aws_account_configmap" { # global variables that come from tf make sense not to be committed to repo, to be consumed by kustomize itself, not pods, through argocd cmp
#  yaml_body = <<-YAML
#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: global-variables
#  namespace: globalvars
#data:
#  TF_ACCOUNT_ID: "${data.aws_caller_identity.current.account_id}"
#  TF_CLUSTER_NAME: "${local.name}"
#  TF_REGION: "${local.region}"
#  TF_ECR_REPO: "${module.ecr.repository_url}"
#  TF_DOMAIN: "${local.domain}"
#  YAML
#  depends_on = [
#    #helm_release.argo_cd
#    module.eks
#  ]
#}



#resource "kubectl_manifest" "aws_account_configmap" {
#  yaml_body = <<-YAML
#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: aws-account
#  namespace: argocd
#data:
#  aws-account: "${data.aws_caller_identity.current.account_id}"
#  YAML
#
#  depends_on = [
#    #module.eks
#  ]
#}

#resource "kubectl_manifest" "aws_account_configmap" { # "${data.aws_caller_identity.current.account_id}"
#  yaml_body = <<-YAML
#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: global-variables
#  namespace: argocd
#data:
#  AWS_ACCOUNT_ID: "${data.aws_caller_identity.current.account_id}"
#  YAML
#
#  depends_on = [
#    #module.eks
#  ]
#}

###############################################################################
# Elasticsearch
###############################################################################

# Create es random password.
resource "random_password" "elastic_password" {
  length           = 28
  special          = true
  override_special = "!$%&()+-?_~" # special character whitelist
}