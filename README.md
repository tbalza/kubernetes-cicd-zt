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

<details>
<summary><h3 style="display: inline;">Git</h3> (This step can be ignored if you already have Git set up)</summary>

- Generate SSH keys (Mac)
  ```bash
  # Main
  ssh-keygen -t rsa -b 4096 -C "tomas.balza@gmail.com" -f ~/.ssh/github-personal && \
  ssh-add -K ~/.ssh/github-personal && \
  pbcopy < ~/.ssh/github-personal.pub # https://github.com/settings/keys (New SSH Key, Paste)
  ```
  ```bash
  # Collab
  ssh-keygen -t rsa -b 4096 -C "tomas.balza+github.collab@gmail.com" -f ~/.ssh/github-personal-collab && \
  ssh-add -K ~/.ssh/github-personal-collab && \
  pbcopy < ~/.ssh/github-personal-collab.pub # https://github.com/settings/keys (New SSH Key, Paste)
  ```
- Managing Multiple Accounts
  ```bash
  mkdir -p ~/.ssh && cat << 'EOF' > ~/.ssh/config
  # Default account `git@github.com` # current GH user: tbalza-collab
  Host github.com
       HostName github.com
       User git
       IdentityFile ~/.ssh/github-personal-collab
       IdentitiesOnly yes
  
  # Alternate account `git@github.com-collab` # current GH user: tbalza
  Host github.com-collab
       HostName github.com
       User git
       IdentityFile ~/.ssh/github-personal
       IdentitiesOnly yes
  EOF
  ```
- Setting Git Global User
  ```bash
  git config --global user.name "tbalza-collab" && \
  git config --global user.email "tomas.balza+github.collab@gmail.com"
  ```
</details>

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

## Creating GitHub Repo and Webhooks

Create repo:
```bash
gh repo create kubernetes-cicd-zt.git --public
```

To create 2 [webhooks](https://docs.github.com/en/webhooks/using-webhooks/creating-webhooks). You can define your domain first with,
```bash
export KCICD_DOMAIN="tbalza.net" # (replace with your domain)
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

The following is the minimal configuration required. (All the other manifests and pipeline scripts are dynamic)

### Cloning the Repository
```bash
cd ~ && \
git clone https://github.com/tbalza/kubernetes-cicd-zt.git && \
cd kubernetes-cicd-zt # commands and paths are relative to ~/kubernetes-cicd-zt/ # open # pycharm
```
### Configuring DNS & GitHub Tokens
Create a `terraform.tfvars` template (Credentials won't be committed due to .gitignore)

  ```bash
  cat << 'EOF' > ~/kubernetes-cicd-zt/terraform/01-eks-cluster/terraform.tfvars
  CFL_API_TOKEN       = ""
  CFL_ZONE_ID         = ""
  ARGOCD_GITHUB_TOKEN = ""
  ARGOCD_GITHUB_USER  = ""
  EOF
  ```

Follow the links bellow to create the tokens to update `terraform.tfvars` with:

- [Create Cloudflare API Token](https://dash.cloudflare.com/profile/api-tokens) The "Zone ID" and "Create your API token" are found scrolling down in the Overview page. Create a "Custom token" with the following permissions:
  - All accounts
    - Access: Mutual TLS Certificates:Edit
    - Account Settings:Edit
  - All zones
    - Zone Settings:Edit
    - Zone:Edit
    - SSL and Certificates:Edit
    - DNS:Edit

- [Create GitHub Personal Access Token](https://github.com/settings/tokens/) Click on "Generate new token (Classic)", tick "repo" permissions, and "Generate token" at the bottom.

### Terraform
Edit your domain and repo URL in `terraform/01-eks-cluster/env-.auto.tfvars`, the rest can be left unchanged:
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
  template:
    spec:
      source:
        repoURL: https://github.com/<your-user>/kubernetes-cicd-zt.git
```

## Pushing Configuration Changes
Link project directory to your own repo, commit and push changes:
```bash
export KCICD_USER="$(git config --global user.name)" && \
git remote set-url origin git@github.com:"$KCICD_USER"/kubernetes-cicd-zt.git && \
git add . && \
git commit -m "configuration complete" && \
git push origin main
# git remote -v # to check origin
```

## Provisioning the Cluster

Initialize TF working directories to downloads plugins, modules and set up the state backend:
```bash
terraform -chdir="terraform/01-eks-cluster/" init && \
terraform -chdir="terraform/02-argocd/" init
```

Provision infra and trigger deployment:
```bash
terraform -chdir="terraform/01-eks-cluster/" apply -auto-approve && \
terraform -chdir="terraform/02-argocd/" apply -auto-approve
```

- Useful Commands During Deployment
  ```bash
  # Get ArgoCD's pods
  kubectl get pods -n argocd
  
  # Portforward ArgoCD to https://localhost:8080
  kubectl port-forward svc/argo-cd-argocd-server -n argocd 8080:443
  
  # Portforward Jenkins to http://localhost:8181
  kubectl port-forward svc/jenkins -n jenkins 8181:8080
  
  # Check DNS propagation status
  dig +short argocd.tbalza.net
  ````

  ```yaml 
  # SSM Parameter Store (Contains Generated Passwords)
  https://us-east-1.console.aws.amazon.com/systems-manager/parameters?region=us-east-1
  
  # Domains
  argocd.tbalza.net # admin
  jenkins.tbalza.net # admin
  django.tbalza.net # admin
  sonarqube.tbalza.net # sonar
  grafana.tbalza.net # admin
  kibana.tbalza.net # admin
  ```

## Removing Resources

Creating AWS resources will incur costs. After you're done, you can run this command to delete everything:

```bash
terraform -chdir="terraform/02-argocd/" destroy ; \
terraform -chdir="terraform/01-eks-cluster/" destroy
```

## Local Django Development

Create `.env` file with the following variables:
```bash
cat << 'EOF' > ~/kubernetes-cicd-zt/django-todo/.env
DB_NAME=dbname
DB_USERNAME=user
DB_PASSWORD=password
DB_HOST=postgres # local uses postgres in docker-compose. remote uses rds endpoint
DB_PORT=5432
SECRET_KEY="your_secret_key_here"
DEBUG="True"
STATIC_ROOT=/static
DOMAIN="*" # allowed hosts
```
Use [docker-compose](https://docs.docker.com/desktop/install/mac-install/) to mimic the deployment setup with RDS locally:
```bash
cd ~/kubernetes-cicd-zt/django-todo && \
docker-compose up
```

Browse `http://0.0.0.0:8000/` to acces the Django "to-do" app that connects to a local Postgres DB and uses Tailwind for the front-end.

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