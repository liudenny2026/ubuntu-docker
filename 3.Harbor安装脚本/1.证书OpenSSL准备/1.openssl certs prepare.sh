#!/bin/bash

# 检查是否为 Ubuntu 环境
if [ ! -f /etc/os-release ]; then
    echo "错误: 无法检测操作系统信息"
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    echo "警告: 此脚本专为 Ubuntu 环境设计，当前系统为: $PRETTY_NAME"
    echo "是否继续? (y/n)"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
        echo "脚本已终止"
        exit 0
    fi
fi

echo "========================================"
echo "Harbor 证书自动部署脚本"
echo "目标域名: myregistry.denny.com"
echo "========================================"
echo ""

# 检查是否已安装 openssl
if ! command -v openssl &> /dev/null; then
    echo "错误: 未检测到 openssl，正在安装..."
    sudo apt-get update
    sudo apt-get install -y openssl
    echo "openssl 安装完成"
fi

# 定义域名
DOMAIN="myregistry.denny.com"

# 检查是否已存在证书文件
EXISTING_CA_FILES=""
EXISTING_DOMAIN_FILES=""

if [ -f "ca.key" ]; then EXISTING_CA_FILES="$EXISTING_CA_FILES ca.key"; fi
if [ -f "ca.crt" ]; then EXISTING_CA_FILES="$EXISTING_CA_FILES ca.crt"; fi
if [ -f "${DOMAIN}.key" ]; then EXISTING_DOMAIN_FILES="$EXISTING_DOMAIN_FILES ${DOMAIN}.key"; fi
if [ -f "${DOMAIN}.csr" ]; then EXISTING_DOMAIN_FILES="$EXISTING_DOMAIN_FILES ${DOMAIN}.csr"; fi
if [ -f "${DOMAIN}.crt" ]; then EXISTING_DOMAIN_FILES="$EXISTING_DOMAIN_FILES ${DOMAIN}.crt"; fi
if [ -f "${DOMAIN}.cert" ]; then EXISTING_DOMAIN_FILES="$EXISTING_DOMAIN_FILES ${DOMAIN}.cert"; fi
if [ -f "v3.ext" ]; then EXISTING_DOMAIN_FILES="$EXISTING_DOMAIN_FILES v3.ext"; fi

if [ -n "$EXISTING_CA_FILES" ] || [ -n "$EXISTING_DOMAIN_FILES" ]; then
    echo "警告: 检测到以下证书文件已存在:"
    if [ -n "$EXISTING_CA_FILES" ]; then
        for file in $EXISTING_CA_FILES; do
            echo "  - $file"
        done
    fi
    if [ -n "$EXISTING_DOMAIN_FILES" ]; then
        for file in $EXISTING_DOMAIN_FILES; do
            echo "  - $file"
        done
    fi
    echo ""
    echo "是否删除这些文件并重新生成? (y/n)"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
        echo "脚本已终止"
        exit 0
    fi

    echo ""
    echo "正在删除现有证书文件..."
    if [ -n "$EXISTING_CA_FILES" ]; then
        for file in $EXISTING_CA_FILES; do
            rm -f "$file"
            if [ $? -eq 0 ]; then
                echo "✓ 已删除: $file"
            else
                echo "✗ 删除失败: $file"
                exit 1
            fi
        done
    fi
    if [ -n "$EXISTING_DOMAIN_FILES" ]; then
        for file in $EXISTING_DOMAIN_FILES; do
            rm -f "$file"
            if [ $? -eq 0 ]; then
                echo "✓ 已删除: $file"
            else
                echo "✗ 删除失败: $file"
                exit 1
            fi
        done
    fi
    echo ""
fi

echo "步骤 1/6: 生成 CA 证书私钥..."
openssl genrsa -out ca.key 4096
if [ $? -ne 0 ]; then
    echo "错误: CA 私钥生成失败"
    exit 1
fi
echo "✓ CA 私钥生成成功: ca.key"
echo ""

echo "步骤 2/6: 生成 CA 证书..."
openssl req -x509 -new -nodes -sha512 -days 3650 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=MyPersonal Root CA" \
    -key ca.key \
    -out ca.crt
if [ $? -ne 0 ]; then
    echo "错误: CA 证书生成失败"
    exit 1
fi
echo "✓ CA 证书生成成功: ca.crt"
echo ""

echo "步骤 3/6: 生成服务器私钥..."
openssl genrsa -out ${DOMAIN}.key 4096
if [ $? -ne 0 ]; then
    echo "错误: 服务器私钥生成失败"
    exit 1
fi
echo "✓ 服务器私钥生成成功: ${DOMAIN}.key"
echo ""

echo "步骤 4/6: 生成证书签名请求 (CSR)..."
openssl req -sha512 -new \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=${DOMAIN}" \
    -key ${DOMAIN}.key \
    -out ${DOMAIN}.csr
if [ $? -ne 0 ]; then
    echo "错误: CSR 生成失败"
    exit 1
fi
echo "✓ CSR 生成成功: ${DOMAIN}.csr"
echo ""

echo "步骤 5/6: 生成 x509 v3 扩展文件..."
cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=${DOMAIN}
EOF
echo "✓ 扩展文件生成成功: v3.ext"
echo ""

echo "步骤 6/6: 生成服务器证书..."
openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in ${DOMAIN}.csr \
    -out ${DOMAIN}.crt
if [ $? -ne 0 ]; then
    echo "错误: 服务器证书生成失败"
    exit 1
fi
echo "✓ 服务器证书生成成功: ${DOMAIN}.crt"
echo ""

echo "========================================"
echo "证书生成完成!"
echo "========================================"
echo "生成的文件列表:"
echo "  - ca.key         (CA 私钥)"
echo "  - ca.crt         (CA 证书)"
echo "  - ${DOMAIN}.key  (服务器私钥)"
echo "  - ${DOMAIN}.csr  (证书签名请求)"
echo "  - ${DOMAIN}.crt  (服务器证书)"
echo "  - v3.ext         (扩展配置文件)"
echo "========================================"
echo ""

# 询问是否部署证书到 Harbor 和 Docker
echo "是否将证书部署到 Harbor 和 Docker? (y/n)"
read -r deploy_response
if [[ "$deploy_response" != "y" && "$deploy_response" != "Y" ]]; then
    echo "跳过部署步骤"
    exit 0
fi

echo ""
echo "========================================"
echo "部署证书到 Harbor 和 Docker"
echo "========================================"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "注意: 部署证书需要 root 权限，使用 sudo 执行..."
    SUDO="sudo"
else
    SUDO=""
fi

# 创建 Harbor 证书目录
echo "步骤 1/4: 创建 Harbor 证书目录..."
${SUDO} mkdir -p /data/cert
echo "✓ Harbor 证书目录创建完成: /data/cert"
echo ""

# 复制证书到 Harbor 目录
echo "步骤 2/4: 复制证书到 Harbor 目录..."
${SUDO} cp ${DOMAIN}.crt /data/cert/
${SUDO} cp ${DOMAIN}.key /data/cert/
echo "✓ 证书已复制到 /data/cert/"
echo ""

# 将 .crt 转换为 .cert 供 Docker 使用
echo "步骤 3/4: 生成 Docker 证书格式..."
openssl x509 -inform PEM -in ${DOMAIN}.crt -out ${DOMAIN}.cert
echo "✓ Docker 证书生成成功: ${DOMAIN}.cert"
echo ""

# 创建 Docker 证书目录
echo "步骤 4/4: 部署证书到 Docker..."
${SUDO} mkdir -p /etc/docker/certs.d/${DOMAIN}
${SUDO} cp ${DOMAIN}.cert /etc/docker/certs.d/${DOMAIN}/
${SUDO} cp ${DOMAIN}.key /etc/docker/certs.d/${DOMAIN}/
${SUDO} cp ca.crt /etc/docker/certs.d/${DOMAIN}/
echo "✓ 证书已部署到 /etc/docker/certs.d/${DOMAIN}/"
echo ""

# 重启 Docker 服务
echo "是否重启 Docker 服务? (y/n)"
read -r docker_response
if [[ "$docker_response" == "y" || "$docker_response" == "Y" ]]; then
    ${SUDO} systemctl restart docker
    if [ $? -eq 0 ]; then
        echo "✓ Docker 服务重启成功"
    else
        echo "警告: Docker 服务重启失败，请手动重启"
    fi
fi

echo ""
echo "========================================"
echo "部署完成!"
echo "========================================"
echo "证书文件已部署到以下位置:"
echo ""
echo "Harbor 目录:"
echo "  /data/cert/${DOMAIN}.crt"
echo "  /data/cert/${DOMAIN}.key"
echo ""
echo "Docker 目录:"
echo "  /etc/docker/certs.d/${DOMAIN}/${DOMAIN}.cert"
echo "  /etc/docker/certs.d/${DOMAIN}/${DOMAIN}.key"
echo "  /etc/docker/certs.d/${DOMAIN}/ca.crt"
echo ""
echo "========================================"
echo "配置示例结构:"
echo "/etc/docker/certs.d/"
echo "  └── ${DOMAIN}"
echo "     ├── ${DOMAIN}.cert  <-- Server certificate signed by CA"
echo "     ├── ${DOMAIN}.key   <-- Server key signed by CA"
echo "     └── ca.crt          <-- Certificate authority that signed the registry certificate"
echo "========================================"
