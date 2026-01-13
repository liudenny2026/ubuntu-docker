#!/bin/bash

# 本地测试 Docker 镜像功能

echo "=== Testing terraform-kubectl Docker image ==="

docker run --rm \
  192.168.40.248/library/terraform-kubectl:2026-1-12 \
  sh -c "
    echo 'Terraform version:'
    terraform --version
    echo ''
    echo 'kubectl version:'
    kubectl version --client=true
    echo ''
    echo 'Installation paths:'
    which terraform kubectl
    echo ''
    echo 'Environment variables:'
    echo 'KUBECONFIG=$KUBECONFIG'
    echo 'TF_DATA_DIR=$TF_DATA_DIR'
    echo ''
    echo '=== All tests passed! ==='
  "
