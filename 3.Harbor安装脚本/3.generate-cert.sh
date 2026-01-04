#!/bin/bash

######################### 配置变量 ###########################
HARBOR_IP="192.168.40.248"  # Harbor服务IP地址
CERT_DIR="/data/cert"       # 证书目录

######################### 前置检查 ###########################
# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本或以 root 用户身份运行"
    exit 1
fi

# 检查openssl命令是否存在
if ! command -v openssl > /dev/null 2>&1; then
    echo "错误：未找到 openssl 命令，请先安装"
    exit 1
fi

######################### 生成证书 ###########################
echo "===== 生成SSL证书 ====="

# 创建证书目录
echo "创建证书目录: $CERT_DIR"
sudo mkdir -p $CERT_DIR

# 检查并删除现有证书
echo "检查现有证书..."
if [ -d "$CERT_DIR" ] && [ "$(ls -A $CERT_DIR 2>/dev/null)" ]; then
    echo "检测到现有证书，正在删除..."
    sudo rm -f $CERT_DIR/*.crt $CERT_DIR/*.key $CERT_DIR/*.csr $CERT_DIR/*.srl $CERT_DIR/*.pem
    echo "现有证书已删除"
else
    echo "证书目录为空，无需清理"
fi
echo ""

# 生成CA私钥
echo "生成CA私钥..."
sudo openssl genrsa -out $CERT_DIR/ca.key 4096
if [ $? -ne 0 ]; then
    echo "错误：生成CA私钥失败"
    exit 1
fi

# 生成CA证书 (10年有效期)
echo "生成CA证书 (有效期10年)..."
sudo openssl req -new -x509 -days 3650 -key $CERT_DIR/ca.key \
    -out $CERT_DIR/ca.crt -sha256 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Harbor CA/OU=IT/CN=Harbor Root CA"
if [ $? -ne 0 ]; then
    echo "错误：生成CA证书失败"
    exit 1
fi

# 生成服务器私钥
echo "生成服务器私钥..."
sudo openssl genrsa -out $CERT_DIR/server.key 2048
if [ $? -ne 0 ]; then
    echo "错误：生成服务器私钥失败"
    exit 1
fi

# 创建临时OpenSSL配置文件
cat > /tmp/openssl.cnf << EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[ req_distinguished_name ]
C = CN
ST = Beijing
L = Beijing
O = Harbor
OU = IT
CN = $HARBOR_IP

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $HARBOR_IP
DNS.1 = harbor.local
DNS.2 = myharbor.com
EOF

# 生成服务器证书签名请求(CSR)
echo "生成服务器证书签名请求..."
sudo openssl req -new -key $CERT_DIR/server.key -out $CERT_DIR/server.csr \
    -config /tmp/openssl.cnf
if [ $? -ne 0 ]; then
    echo "错误：生成CSR失败"
    exit 1
fi

# 创建CA签名配置文件
cat > /tmp/openssl-ca.cnf << EOF
[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $HARBOR_IP
DNS.1 = harbor.local
DNS.2 = myharbor.com
EOF

# 使用CA证书签名服务器证书 (10年有效期)
echo "使用CA签名服务器证书 (有效期10年)..."
sudo openssl x509 -req -in $CERT_DIR/server.csr -CA $CERT_DIR/ca.crt \
    -CAkey $CERT_DIR/ca.key -CAcreateserial -out $CERT_DIR/server.crt \
    -days 3650 -sha256 -extfile /tmp/openssl-ca.cnf -extensions v3_req
if [ $? -ne 0 ]; then
    echo "错误：签名服务器证书失败"
    exit 1
fi

# 清理临时配置文件和CSR
rm -f /tmp/openssl.cnf /tmp/openssl-ca.cnf $CERT_DIR/server.csr

# 设置证书权限
sudo chmod 644 $CERT_DIR/ca.crt
sudo chmod 644 $CERT_DIR/server.crt
sudo chmod 600 $CERT_DIR/server.key
sudo chmod 600 $CERT_DIR/ca.key

# 验证证书
echo "验证证书..."
echo "CA证书信息:"
sudo openssl x509 -in $CERT_DIR/ca.crt -text -noout | grep -E "Subject:|Not After|Issuer:"
echo ""
echo "服务器证书信息:"
sudo openssl x509 -in $CERT_DIR/server.crt -text -noout | grep -E "Subject:|Not After:|Issuer:"
echo ""
echo "验证服务器证书SAN扩展:"
sudo openssl x509 -in $CERT_DIR/server.crt -text -noout | grep -A1 "Subject Alternative Name"
echo ""
echo "验证证书链:"
sudo openssl verify -CAfile $CERT_DIR/ca.crt $CERT_DIR/server.crt

echo ""
echo "===== 证书生成完成! ====="
echo "证书文件位置: $CERT_DIR"
echo ""
echo "生成的证书文件:"
echo "  - ca.crt       : CA根证书 (客户端信任用)"
echo "  - ca.key       : CA私钥 (重要，请妥善保管)"
echo "  - server.crt   : 服务器证书"
echo "  - server.key   : 服务器私钥"
echo ""
echo "Docker客户端信任配置:"
echo "  sudo mkdir -p /etc/docker/certs.d/$HARBOR_IP"
echo "  sudo cp $CERT_DIR/ca.crt /etc/docker/certs.d/$HARBOR_IP/ca.crt"
echo "  sudo systemctl restart docker"
