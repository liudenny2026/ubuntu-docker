#!/bin/bash

# kubectl 自动安装脚本 (适用于 Ubuntu 系统)
set -e

# 1. 获取最新版本并下载
echo "正在获取最新 kubectl 版本..."
VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
echo "最新版本: $VERSION"

ARCH=$(dpkg --print-architecture)
DOWNLOAD_URL="https://dl.k8s.io/release/$VERSION/bin/linux/$ARCH/kubectl"

# 2. 下载并安装
echo "正在下载 kubectl..."
curl -LO "$DOWNLOAD_URL"
chmod +x kubectl
mv kubectl /usr/local/bin/

# 3. 创建软链接
ln -sf /usr/local/bin/kubectl /usr/bin/kubectl

# 4. 添加命令自动补全
echo "正在配置命令自动补全..."

# 为 bash 添加补全
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

# 为 zsh 添加补全（如果存在 zsh）
if command -v zsh &> /dev/null; then
    kubectl completion zsh | sudo tee /usr/share/zsh/vendor-completions/_kubectl > /dev/null
fi

# 添加到当前用户的 shell 配置
if [ -n "$BASH_VERSION" ]; then
    if ! grep -q "kubectl completion" ~/.bashrc 2>/dev/null; then
        echo 'source <(kubectl completion bash)' >> ~/.bashrc
        echo "已添加自动补全到 ~/.bashrc"
    fi
fi

if [ -n "$ZSH_VERSION" ]; then
    if ! grep -q "kubectl completion" ~/.zshrc 2>/dev/null; then
        echo 'source <(kubectl completion zsh)' >> ~/.zshrc
        echo "已添加自动补全到 ~/.zshrc"
    fi
fi

# 5. 验证安装
echo ""
echo "============================================="
echo "kubectl 安装完成！"
echo "============================================="
echo "版本: $(kubectl version --client --short 2>/dev/null)"
echo "路径: $(which kubectl)"
echo ""
echo "提示: 重新登录终端后生效，或执行: source ~/.bashrc"
echo "============================================="
