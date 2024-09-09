# Zero-Touch Provisioning & Deployment of Kubernetes CI/CD Pipeline

<img src="diagram.png" alt="Your image description" width="852"/>

A Proof of Concept (PoC) that provisions a fully operational EKS cluster using terraform, and deploys a complete Django application along with an interconnected CI/CD stack made of ArgoCD, Jenkins, Prometheus, Grafana, Elasticsearch, Fluentbit, and Kibana.

All with dynamic configuration values, CNAME entries, secure credentials, and requires no manual intervention after issuing one terraform apply command.

A full breakdown can be found at my [blogpost](https://tbalza.net/zero-touch-provisioning-deployment-of-kubernetes-ci/cd-pipeline/)

> **Warning**: Creating resources in AWS will incur costs. Remember to use the `terraform destroy` command at the end to remove all resources after you're finished.

## Directory Structure

```bash
┌── argo-apps                       # Deployment Stage Addons/Apps
│   ├── argocd 
│   ├── argocd-image-updater
│   ├── django
│   ├── eck-stack
│   ├── fluent
│   ├── jenkins
│   ├── prometheus
│   └── sonarqube
├── django-todo                     # Main App Developement
└── terraform
    ├── 01-eks-cluster              # Terraform Infra Provisioning Stage
    └── 02-argocd                   # Terraform ArgoCD Boostrap Stage
```

## Requirements
With [Homebrew](https://docs.brew.sh/Installation) (Mac):
```bash
/bin/bash -c “$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Install the necessary CLI tools,
```bash
brew install brew tap hashicorp/tap && brew install hashicorp/tap/terraform # terraform
brew install awscli # aws-cli
brew install helm # helm
brew install kubectl # kubectl
```

Configure the [AWS CLI tool](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) with your user. Optionally create an [Isolated Testing Account](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_tutorials_basic.html) for more granular access control and budget limits.

This assumes you have the credentials that contain your `aws_access_key_id` and your `aws_secret_access_key` for your IAM User with required permissions.

```bash
aws configure
```

## Setting up DNS, and Generating CloudFlare & GitHub Tokens
[Setup Cloudflare DNS Nameservers](https://www.namecheap.com/support/knowledgebase/article.aspx/9607/2210/how-to-set-up-dns-records-for-your-domain-in-a-cloudflare-account/). (ExternalDNS supports Route53, GKE, DigitalOcean, GoDaddy etc. but currently this PoC is configured to work with CloudFlare DNS Service out of the box)

[Create Cloudflare API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) and set env vars,
```bash
export TF_VAR_CFL_API_TOKEN = "your-cloudflare-token"
export TF_VAR_CFL_ZONE_ID = "your-cloudflare-zoneid"
```

[Create GitHub Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens/) and set env vars,

```bash
export TF_VAR_ARGOCD_GITHUB_TOKEN = "you-github-token" # token and login password are two different things
export TF_VAR_ARGOCD_GITHUB_USER = "your-github-user"
```
## Cloning the Repository

```bash
git clone https://github.com/tbalza/kubernetes-cicd-zt.git
cd kubernetes-cicd-zt && export KCICD_HOME=$(pwd) # set project's home directory
```

## Creating GitHub Webhooks

In your cloned GH repo settings create 2 [webhooks](https://docs.github.com/en/webhooks/using-webhooks/creating-webhooks):

Via the UI console create entries with the `application/json` content-type,

`https://jenkins.<your-domain.com>/github-webhook/`

`https://argocd.<your-domain.com>/api/webhook`

The rest of the settings are left default.

## Configuring Cluster Settings
Edit your domain and repo URL in Terraform, the rest can be left unchanged:
```bash
open /terraform/01-eks-cluster/set_up_eks_cluster.tf 
```
```hcl
locals {
  name            = "django-production" # cluster name
  region          = "us-east-1"
  domain          = "<your-domain>.com"
  repo_url        = "https://github.com/<your-user>/kubernetes-cicd-zt.git"
```
Edit the repoURL value in ArgoCD's 'ApplicationSet':
```bash
open /argo-apps/argocd/applicationset.yaml 
```
```yaml
spec: # add sed/yq command
  generators:
    - git:
        repoURL: https://github.com/<your-user>/kubernetes-cicd-zt.git
```
And finally commit and push saved changes
```bash
git add .
git commit -m "configuration complete"
git push origin main
```

## Provisioning the Cluster

Before you apply changes the first time, you need to initialize TF working directories, download plugins and modules and set up backend for storing your infrastructure's state usig the `init` command:
```bash
terraform -chdir="$KCICD_HOME/terraform/01-eks-cluster/" init
terraform -chdir="$KCICD_HOME/terraform/02-argocd/" init
```

Provision and deploy all apps with single compound `apply` command:
```bash
terraform -chdir="$KCICD_HOME/terraform/01-eks-cluster/" apply -auto-approve && terraform terraform -chdir="$KCICD_HOME/terraform/02-argocd/" apply -auto-approve
```

> `terraform/01-eks-cluser` Provisions infrastructure, and core addons that don't change often. While `terraform/02-argocd` Bootstraps ArgoCD via helm, which will in turn deploy the rest of the apps. Separating these stages into two TF state files reduces future maintenance issues

## Final Results

### Provisioning
After executing `terraform apply -auto-approve`, the provisioning stage will set up the EKS cluster with Node Groups, Access Entries, along with its core addons (CoreDNS, Kube-Proxy, VPC-CNI, EBS CSI Driver, AWS Load Balancer Controller, ExternalDNS, External Secrets Operator) and resources like IAM Policies/Roles/Security Groups, ACM, VPC, RDS, SSM, Application Load Balancer, and ECR.

This provisioning cycle takes about ~25 minutes.

### Deployment

After the first stage succeeds, Terraform will automatically bootstrap ArgoCD using values generated dynamically while provisioning, where it will now "take over" and deploy a fully configured and interconnected CI/CD pipeline with Sonarqube, Jenkins, ArgoCD Image Updater, Django, ElasticSearch, Fluentbit, Kibana, Prometheus and Grafana.

After around ~10 minutes you'll be able to access all of the app console UIs via their subdomain:

- django.yourdomain.com
- argocd.yourdomain.com
- sonarqube.yourdomain.com
- jenkins.yourdomain.com
- kibana.yourdomain.com
- grafana.yourdomain.com

The dynamically generated passwords to access each service will be available via the SSM Parameter Store console in AWS. 

## Remove Resources

After you're done, you can run this command to delete all resources.

```bash
terraform -chdir="$KCICD_HOME/terraform/02-argocd/" destroy ; terraform -chdir="$KCICD_HOME/terraform/01-eks-cluster/" destroy
```

## Roadmap
Future enhancements include:

- **Security:** Scope Access Entries, IAM Policies/Roles/Security Groups, SSM, to follow the principle of least privilege. Non-root Django container
- **CI:** Code linting. CI tests
- **Multi Environment Setup:** Implement TF workspaces with .tfvars to enable Dev, Staging, QA, Prod, environments. Implement remote state management.
- **SSO:** Configure Single Sign On for user management, and integrate with IAM permissions
- **Software Development Life Cycle:** Implement examples with trunk-based development and tags
- **Repo Structure:** Fix long .tf files, create directories for customer facing apps along with corresponding ApplicationSets.
- **Crucial Addons:** Install backup/DR solutions, autoscaling, cost tracking, etc.