#!/bin/bash

# 卸载旧版本Docker（如果存在）
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# 直接安装Docker和docker-compose
echo "开始安装Docker和docker-compose..."

# 更新包列表
sudo apt-get update

# 安装必要的依赖包
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 安装Docker
echo "安装Docker..."
sudo apt install -y docker.io

# 启动并启用Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 安装docker-compose
echo "安装docker-compose..."
sudo apt -y install docker-compose

# 将当前用户添加到docker组
echo "将当前用户 $USER 添加到docker组..."
sudo usermod -aG docker $USER
echo "注意：需要重新登录以应用Docker组权限，或运行 'newgrp docker' 命令"

# 配置Docker国内镜像源
sudo mkdir -p /etc/docker

# 创建新配置文件
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://ccr.ccs.tencentyun.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# 重启Docker服务以应用配置
echo "重新加载systemd配置..."
sudo systemctl daemon-reload

echo "重启Docker服务..."
sudo systemctl restart docker

echo "检查Docker服务状态..."
sudo systemctl status docker --no-pager -l

echo "Docker安装完成！"