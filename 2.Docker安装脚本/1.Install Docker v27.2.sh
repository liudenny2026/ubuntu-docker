#!/bin/bash
# 1. 更新系统并安装依赖
sudo apt update
sudo apt install -y ca-certificates curl gnupg net-tools lsb-release

# 2. 添加Docker官方GPG密钥
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. 添加Docker仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. 安装特定版本的Docker
sudo apt update
VERSION_STRING=5:27.2.1-1~ubuntu.24.04~noble
sudo apt-get install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin

# 5. 启用Docker服务
sudo systemctl enable docker
sudo systemctl start docker

# 6. 验证Docker安装版本
echo "======================================"
echo "Docker 安装完成！"
echo "======================================"
echo "Docker 版本信息："
docker --version
echo ""
echo "Docker 详细信息："
docker info --format "Docker版本: {{.ServerVersion}}" 2>/dev/null || docker version | grep "Server:"
echo ""
echo "容器运行时状态："
sudo systemctl is-active docker
echo "======================================"
