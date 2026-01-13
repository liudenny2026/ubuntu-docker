# Use Ubuntu LTS as base image for stability
FROM ubuntu:22.04

LABEL maintainer="DevOps Team" \
      description="Terraform and kubectl image for GitLab CI/CD" \
      version="1.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TF_VERSION=1.14.3
ENV K8S_VERSION=v1.35.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    git \
    openssh-client \
    jq \
    bash \
    vim \
    wget \
    dnsutils \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN if [ "$TF_VERSION" = "latest" ]; then \
        TF_LATEST=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version') && \
        echo "Installing Terraform version: $TF_LATEST"; \
    else \
        TF_LATEST=$TF_VERSION; \
    fi && \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_LATEST}/terraform_${TF_LATEST}_linux_amd64.zip" -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform.zip && \
    terraform --version

# Install kubectl
RUN if [ "$K8S_VERSION" = "latest" ]; then \
        K8S_LATEST=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt) && \
        echo "Installing kubectl version: $K8S_LATEST"; \
    else \
        K8S_LATEST=$K8S_VERSION; \
    fi && \
    curl -fsSL "https://dl.k8s.io/release/$K8S_LATEST/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    kubectl version --client=true

# Install Kubernetes provider for Terraform
RUN mkdir -p /home/terraform_kubectl/.terraform.d/plugins/registry.terraform.io/hashicorp/kubernetes/2.32.0/linux_amd64 && \
    curl -fsSL "https://releases.hashicorp.com/terraform-provider-kubernetes/2.32.0/terraform-provider-kubernetes_2.32.0_linux_amd64.zip" -o /tmp/k8s-provider.zip && \
    unzip -o /tmp/k8s-provider.zip -d /home/terraform_kubectl/.terraform.d/plugins/registry.terraform.io/hashicorp/kubernetes/2.32.0/linux_amd64 && \
    rm /tmp/k8s-provider.zip && \
    chmod +x /home/terraform_kubectl/.terraform.d/plugins/registry.terraform.io/hashicorp/kubernetes/2.32.0/linux_amd64/terraform-provider-kubernetes && \
    echo "Kubernetes provider installed successfully"

# Create a dedicated user for security
RUN groupadd -r terraform_kubectl && useradd -r -g terraform_kubectl -m -s /bin/bash terraform_kubectl
USER terraform_kubectl
WORKDIR /home/terraform_kubectl

# Create directories for configuration and state
RUN mkdir -p ~/.kube && \
    mkdir -p ~/.terraform.d/plugin-cache && \
    mkdir -p /home/terraform_kubectl/workspace

# Set up environment variables for Terraform
ENV TF_CLI_CONFIG_FILE=/home/terraform_kubectl/.terraformrc
ENV TF_DATA_DIR=/home/terraform_kubectl/.terraform.d

# Create a basic terraform configuration
RUN echo 'plugin_cache_dir = "/home/terraform_kubectl/.terraform.d/plugin-cache"' > ~/.terraformrc

# Create a default kubeconfig directory and file
RUN touch ~/.kube/config
ENV KUBECONFIG=/home/terraform_kubectl/.kube/config

# Set working directory
WORKDIR /workspace

# Verify installations
RUN terraform version && kubectl version --client=true

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD terraform version && kubectl version --client=true || exit 1

# Set default command
CMD ["/bin/bash"]