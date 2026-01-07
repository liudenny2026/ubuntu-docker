#!/bin/bash

echo "========================================"
echo "客户端 Docker 访问 Harbor 配置脚本"
echo "Harbor 地址: myregistry.denny.com"
echo "========================================"
echo ""

# 定义变量
HARBOR_SERVER="myregistry.denny.com"
SERVER_CERT_DIR="/etc/docker/certs.d/${HARBOR_SERVER}"
CLIENT_CERT_DIR="/etc/docker/certs.d/${HARBOR_SERVER}"

# 步骤1: 从服务器获取 CA 证书
echo "步骤 1/3: 从服务器获取 CA 证书..."
echo "请确保服务器 IP 地址正确且已配置 SSH 免密登录"
echo "提示: 可以使用 ssh-copy-id 配置免密登录"
echo ""

read -p "输入服务器 IP 地址 [192.168.40.248]: " SERVER_IP
SERVER_IP=${SERVER_IP:-192.168.40.248}

# 创建客户端证书目录
if [ ! -d "$CLIENT_CERT_DIR" ]; then
    echo "创建客户端证书目录: $CLIENT_CERT_DIR"
    sudo mkdir -p "$CLIENT_CERT_DIR"
else
    echo "客户端证书目录已存在: $CLIENT_CERT_DIR"
fi

# 从服务器复制 CA 证书
if [ -f "$CLIENT_CERT_DIR/ca.crt" ]; then
    echo "警告: 本地已存在 ca.crt 文件"
    read -p "是否覆盖? (y/n): " OVERWRITE
    if [[ "$OVERWRITE" == "y" || "$OVERWRITE" == "Y" ]]; then
        scp root@${SERVER_IP}:${SERVER_CERT_DIR}/ca.crt ${CLIENT_CERT_DIR}/
    fi
else
    scp root@${SERVER_IP}:${SERVER_CERT_DIR}/ca.crt ${CLIENT_CERT_DIR}/
fi

if [ $? -eq 0 ]; then
    echo "✓ CA 证书已复制到: ${CLIENT_CERT_DIR}/ca.crt"
else
    echo "✗ CA 证书复制失败"
    exit 1
fi
echo ""

# 步骤2: 验证 CA 证书
echo "步骤 2/3: 验证 Docker 证书..."
if [ -f "$CLIENT_CERT_DIR/ca.crt" ]; then
    echo "✓ CA 证书已配置成功: ${CLIENT_CERT_DIR}/ca.crt"
else
    echo "✗ CA 证书不存在: ${CLIENT_CERT_DIR}/ca.crt"
    exit 1
fi
echo ""

# 步骤3: 重启 Docker 服务
echo "步骤 3/3: 重启 Docker 服务..."
read -p "是否重启 Docker 服务? (y/n) [y]: " RESTART_DOCKER
RESTART_DOCKER=${RESTART_DOCKER:-y}

if [[ "$RESTART_DOCKER" == "y" || "$RESTART_DOCKER" == "Y" ]]; then
    sudo systemctl restart docker
    if [ $? -eq 0 ]; then
        echo "✓ Docker 服务重启成功"
    else
        echo "✗ Docker 服务重启失败，请手动重启"
        exit 1
    fi
else
    echo "跳过 Docker 服务重启，请手动执行: sudo systemctl restart docker"
fi
echo ""

echo "========================================"
echo "配置完成!"
echo "========================================"
echo ""
echo "配置信息:"
echo "  Harbor 地址: ${HARBOR_SERVER}"
echo "  Docker 证书目录: ${CLIENT_CERT_DIR}"
echo ""
echo "现在可以使用以下命令登录 Harbor:"
echo "  docker login ${HARBOR_SERVER}"
echo ""
echo "拉取镜像示例:"
echo "  docker pull ${HARBOR_SERVER}/project/image:tag"
echo ""
echo "========================================"
