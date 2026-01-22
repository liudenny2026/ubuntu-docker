#!/bin/bash

echo "=== 开始安装MetalLB ==="

# 配置kube-proxy的strictARP
echo "1. 配置kube-proxy的strictARP..."
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system

# 部署MetalLB
echo "2. 部署MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

# 验证部署
echo "3. 验证MetalLB部署状态..."
sleep 5
kubectl get pods -n metallb-system

echo "=== MetalLB安装完成 ==="

