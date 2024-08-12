# Use the official Argo CD image as the base
FROM quay.io/argoproj/argocd:latest

# Install gettext for envsubst
USER root
RUN apt-get update && \
    apt-get install -y gettext-base && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch back to the default user
USER argocd