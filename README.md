jenkins webhook

helm repo update

tree -I '.terraform|venv'

sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

rm ~/.kube/config

docker run --rm --platform linux/amd64 tbalza/envsubst2:latest envsubst --version
docker buildx build --platform linux/amd64 -t tbalza/envsubst2:latest --push .

set Cloudflare API token as an environment variable (that will be used by ExternalDNS)
# export TF_VAR_CFL_API_TOKEN=123example
set Cloudflare Zone ID as an environment variable (that will be used by ACM)
# export TF_VAR_CFL_ZONE_ID=123example

# ArgoCD Image Updater GitHub Personal Access Token
export TF_VAR_ARGOCD_GITHUB_TOKEN=123example
export TF_VAR_ARGOCD_GITHUB_USER=123user

# Django local vars

.env
DB_NAME=postgres
DB_USERNAME=user
DB_PASSWORD=pass
DB_HOST=postgres-service
DB_PORT=5432

check "TODO" django

export STATIC_ROOT=/data/static

ALLOWED_HOSTS
Debug=0 (in production)


# cmp envsubst
https://github.com/a8m/envsubst/releases/download/v1.4.2/envsubst-Linux-x86_64

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY =

you are better off separating your infrastructure from your applications.
this would be two different statefiles, and you would need to explicitly handle the removal of the applications running on the cluster first, before destroying the cluster
# Necessary to avoid removing Terraform's permissions too soon before its finished
# cleaning up the resources it deployed inside the cluster
terraform state rm 'module.eks.aws_eks_access_entry.this["cluster_creator"]' || true
terraform state rm 'module.eks.aws_eks_access_policy_association.this["cluster_creator_admin"]' || true

https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2923

Solution

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = try(aws_eks_cluster.this[0].endpoint, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}
output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = try(aws_eks_cluster.this[0].certificate_authority[0].data, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}

----

Before destroy
export KUBECONFIG=~/.kube/config
tf refresh

#helm
kubectl apply -f service_account.yml
helm install app eks/app

#before deploying ingress, run logs in separate terminal
kubectl logs -f -n kube-system \
-l app.kubernetes.io/name=aws-load-balancer-controller

export KUBERNETES_MASTER=https://FAA89D5CCB710D5F4E6AB4F6408A1D25.gr7.us-east-1.eks.amazonaws.com
export KUBECONFIG=~/.kube/config
export KUBE_CONFIG_PATH=~/.kube/config
export DISABLE_TELEMETRY=true #cloud nuke

#consider using aws-iam-authenticator

export TF_LOG=TRACE # most detailed
export TF_LOG=DEBUG # less detailed
export TF_LOG_PATH=terraform.log

kubectl describe svc argo-cd-argocd-server -n argocd
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

--
#argo default pass
                        kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode
#admin, pass node name complete

kubectl get svc -n argocd

Access argocd cli tool: port-forwarded the argo server to localhost port 8080
                            kubectl port-forward svc/argo-cd-argocd-server -n argocd 8080:443

                            #jenkins main (http://localhost:8181)
                            kubectl port-forward svc/jenkins -n jenkins 8181:8080


                        argocd login localhost:8080 --username admin --password PASSWORD

                        argocd login localhost:8080 --username admin --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode) --plaintext

WARNING: server certificate had error: x509: “Argo CD” certificate is not trusted. Proceed insecurely (y/n)? y
'admin:login' logged in successfully

--
#check ENV
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server

#Access Entry
https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2968

#ApplicationSet
-ArgoCD itself? auto manage

ArgoCD +helm/manifest would create the ServiceAccount with the role in the annotations.
In your manifest, just annotate your ServiceAccount with the IAM role arn. 

#pending
-External DNS
-SSL
-Secrets
-finalizers
--move argo ingress outside tf

roles
-assumed role to run tf
https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3020