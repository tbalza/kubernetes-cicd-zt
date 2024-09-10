# Zero-Touch Provisioning & Deployment of Kubernetes CI/CD Pipeline

<img src="diagram.png" alt="Your image description" width="852"/>

A Proof of Concept (PoC) that provisions an EKS cluster using terraform, and deploys a sample full-stack Django application with a working CI/CD pipeline.

A full breakdown can be found at my [blogpost](https://tbalza.net/zero-touch-provisioning-deployment-of-kubernetes-ci/cd-pipeline/)

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

Install the necessary CLI tools using [Homebrew](https://docs.brew.sh/Installation) (Mac):
```bash
brew install git
brew install gh # github cli
brew install brew tap hashicorp/tap && brew install hashicorp/tap/terraform # terraform
brew install awscli
brew install helm
brew install kubectl
```
### AWS CLI
Configure the [AWS CLI tool](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) with your admin IAM User's `aws_access_key_id` and `aws_secret_access_key`

```bash
aws configure
```

### GitHub CLI

Run the `gh` command below, in the options choose SSH, your previously created public key, copy the generated one-time code, and paste the code in the resulting browser window to authenticate:
```bash
gh auth login -w -p ssh -s repo,read:org,gist,admin:public_key,admin:repo_hook && \
gh config set pager cat # disables vim console after command execution
```

## Configuring DNS & GitHub Tokens
[Setup Cloudflare DNS Nameservers](https://www.namecheap.com/support/knowledgebase/article.aspx/9607/2210/how-to-set-up-dns-records-for-your-domain-in-a-cloudflare-account/).
If you bought your domain with another registrar, you can point to Cloudflare's nameservers and have access to their DNS services and API.

(ExternalDNS supports Route53, GKE, DigitalOcean, GoDaddy etc. This PoC is configured to work with Cloudflare DNS Service out of the box, but can be adapted to use most major services)

[Create Cloudflare API Token](https://dash.cloudflare.com/profile/api-tokens) with "All accounts, All Zones" permissions and set env vars. The "Zone ID" is found in the Overview page

[Create GitHub Personal Access Token](https://github.com/settings/tokens/). Click on "Generate new token (Classic)", tick "repo" permissions, and save


Edit `/terraform/01-eks-cluster/sample-dot-tfvars` with the tokens, and rename to `terraform.vars` (credentials won't be committed due to .gitignore)

## Creating GitHub Repo and Webhooks

Create repo:
```bash
gh repo create kubernetes-cicd-zt.git --public
```

To create 2 [webhooks](https://docs.github.com/en/webhooks/using-webhooks/creating-webhooks). You can define your domain first with,
```bash
export KCICD_DOMAIN="yourdomain.com"
```
and execute this whole command in terminal:

```bash
export KCICD_USER="$(git config --global user.name)" && \
echo '{
  "name": "web",
  "active": true,
  "events": ["push"],
  "config": {
    "url": "https://jenkins.'"$KCICD_DOMAIN"'/github-webhook/",
    "content_type": "json"
  }
}' | gh api /repos/"$KCICD_USER"/kubernetes-cicd-zt/hooks --input - && \
echo '{
  "name": "web",
  "active": true,
  "events": ["push"],
  "config": {
    "url": "https://argocd.'"$KCICD_DOMAIN"'/api/webhook/",
    "content_type": "json"
  }
}' | gh api /repos/"$KCICD_USER"/kubernetes-cicd-zt/hooks --input -
```

## Configuring Cluster Settings

### Cloning the Repository
```bash
cd ~ && \
git clone https://github.com/tbalza/kubernetes-cicd-zt.git && \
cd kubernetes-cicd-zt # commands and paths are relative to ~/kubernetes-cicd-zt/
```

### Terraform
Edit your domain and repo URL in `/terraform/01-eks-cluster/env-.auto.tfvars`, the rest can be left unchanged:
```hcl
TF_DOMAIN      = "yourdomain.com"
TF_REPO_URL    = "https://github.com/youruser/kubernetes-cicd-zt.git"
```
### ArgoCD
Edit the repoURL value in ArgoCD's 'ApplicationSet' `/argo-apps/argocd/applicationset.yaml`:
```yaml
spec: # add sed/yq command
  generators:
    - git:
        repoURL: https://github.com/<your-user>/kubernetes-cicd-zt.git
```

## Pushing Configuration Changes
Commit changes, link project directory to your own repo, and push changes:
```bash
git add . && \
git commit -m "configuration complete" && \
git remote add origin git@github.com:"$KCICD_USER"/kubernetes-cicd-zt.git && \
git push origin main
```

## Provisioning the Cluster

Initialize TF working directories to downloads plugins, modules and set up the state backend:
```bash
terraform -chdir="/terraform/01-eks-cluster/" init && \
terraform -chdir="/terraform/02-argocd/" init
```

Provision infra and trigger deployment:
```bash
terraform -chdir="/terraform/01-eks-cluster/" apply -auto-approve && \
terraform -chdir="/terraform/02-argocd/" apply -auto-approve
```

> `terraform/01-eks-cluser` Provisions infrastructure, and core addons that don't change often. While `terraform/02-argocd` Bootstraps ArgoCD via helm, which will in turn deploy the rest of the apps.

## Removing Resources

Creating AWS resources will incur costs. After you're done, you can run this command to delete everything:

```bash
terraform -chdir="/terraform/02-argocd/" destroy ; \
terraform -chdir="/terraform/01-eks-cluster/" destroy
```

## Roadmap
Future enhancements include:
- **GitHub Actions**: Automate initial project setup (not just Provisioning and Deployment)
- **Security:** Scope Access Entries, IAM Policies/Roles/Security Groups, SSM, to follow the principle of least privilege. Non-root Django container
- **CI:** Code linting. CI tests. ECR Docker Caching
- **Multi Environment Setup:** Implement TF workspaces with .tfvars to enable Dev, Staging, QA, Prod, environments. Implement remote state management
- **SSO:** Configure Single Sign On for user management, and integrate with IAM permissions
- **Software Development Life Cycle:** Implement examples with trunk-based development and tags
- **Repo Structure:** Fix long .tf files, create directories for customer facing apps along with corresponding ApplicationSets
- **Crucial Addons:** Install backup/DR solutions, autoscaling, cost tracking, etc.