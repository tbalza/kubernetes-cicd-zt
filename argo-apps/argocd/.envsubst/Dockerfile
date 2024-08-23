# Use Alpine Linux as the base image
FROM alpine:latest

# Define environment variables for software versions
ENV KUSTOMIZE_VERSION="4.5.7"
ENV HELM_VERSION="3.9.0"

# Install required envsubst
RUN apk add --no-cache curl gettext tar gzip

# Install kustomize
RUN curl -L "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" | \
    tar xz -C /usr/local/bin

# Install helm
RUN curl -L "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | \
    tar xz -C /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/linux-amd64

# Add a non-root user 'argocd' and create home directory
RUN adduser -D argocd

# Switch to the 'argocd' user
USER argocd

# Set the working directory
WORKDIR /home/argocd

# Command to keep the container running # check
CMD ["tail", "-f", "/dev/null"]