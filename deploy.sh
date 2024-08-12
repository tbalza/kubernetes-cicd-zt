#!/bin/bash
# Deploy the EKS Cluster
cd 01-eks-cluster
terraform init
terraform apply -auto-approve

# Check for success and deploy Argo CD
if [ $? -eq 0 ]; then
    cd ../02-argocd
    terraform init
    terraform apply -auto-approve
else
    echo "EKS Cluster deployment failed."
    exit 1
fi
