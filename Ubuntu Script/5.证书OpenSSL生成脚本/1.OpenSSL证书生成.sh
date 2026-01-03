#!/bin/bash

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    printf '\033[0;32m[INFO]\033[0m %s\n' "$1"
}

print_error() {
    printf '\033[0;31m[ERROR]\033[0m %s\n' "$1"
}

print_warning() {
    printf '\033[1;33m[WARNING]\033[0m %s\n' "$1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本！"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查 openssl 是否安装
check_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        print_error "openssl 未安装！"
        echo "请先安装 openssl: apt-get install -y openssl"
        exit 1
    fi
}

# 错误处理函数
error_exit() {
    print_error "$1"
    print_info "正在清理临时文件..."
    cd - > /dev/null 2>&1
    cleanup
    exit 1
}

# 清理函数
cleanup() {
    if [ -f "$CERT_DIR/server.csr" ]; then
        rm -f "$CERT_DIR/server.csr"
    fi
    if [ -f "$CERT_DIR/client.csr" ]; then
        rm -f "$CERT_DIR/client.csr"
    fi
    if [ -f "$CERT_DIR/extfile.cnf" ]; then
        rm -f "$CERT_DIR/extfile.cnf"
    fi
    if [ -f "$CERT_DIR/extfile-client.cnf" ]; then
        rm -f "$CERT_DIR/extfile-client.cnf"
    fi
    if [ -f "$CERT_DIR/ca.srl" ]; then
        rm -f "$CERT_DIR/ca.srl"
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "      Docker TLS 证书生成脚本         "
    echo "========================================"
    echo ""

    # 检查运行环境
    check_root
    check_openssl

    # 创建证书目录
    CERT_DIR="/etc/gitlab-runner/certs/client"
    print_info "创建证书目录: $CERT_DIR"
    mkdir -p "$CERT_DIR" || error_exit "无法创建证书目录"

    cd "$CERT_DIR" || error_exit "无法进入证书目录"
    CURRENT_DIR=$(pwd)
    print_info "当前工作目录: $CURRENT_DIR"
    echo ""

    # 生成 CA 私钥
    print_info "生成 CA 私钥..."
    openssl genrsa -out ca-key.pem 4096 || error_exit "生成 CA 私钥失败"

    # 生成 CA 证书
    print_info "生成 CA 证书..."
    openssl req -new -x509 -days 3650 -key ca-key.pem -sha256 -out ca.pem \
        -subj "/CN=DockerCA" || error_exit "生成 CA 证书失败"

    # 生成服务器私钥
    print_info "生成服务器私钥..."
    openssl genrsa -out server-key.pem 4096 || error_exit "生成服务器私钥失败"

    # 生成服务器 CSR
    print_info "生成服务器证书签名请求..."
    openssl req -subj "/CN=docker" -sha256 -new -key server-key.pem \
        -out server.csr || error_exit "生成服务器 CSR 失败"

    # 创建服务器扩展文件
    print_info "创建服务器扩展配置..."
    echo "subjectAltName = DNS:docker,IP:0.0.0.0" > extfile.cnf
    echo "extendedKeyUsage = serverAuth" >> extfile.cnf

    # 用 CA 签名服务器证书
    print_info "用 CA 签名服务器证书..."
    openssl x509 -req -days 3650 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
        -CAcreateserial -out server-cert.pem -extfile extfile.cnf \
        || error_exit "签名服务器证书失败"

    # 生成客户端私钥
    print_info "生成客户端私钥..."
    openssl genrsa -out key.pem 4096 || error_exit "生成客户端私钥失败"

    # 生成客户端 CSR
    print_info "生成客户端证书签名请求..."
    openssl req -subj "/CN=client" -new -key key.pem \
        -out client.csr || error_exit "生成客户端 CSR 失败"

    # 创建客户端扩展文件
    print_info "创建客户端扩展配置..."
    echo "extendedKeyUsage = clientAuth" > extfile-client.cnf

    # 用 CA 签名客户端证书
    print_info "用 CA 签名客户端证书..."
    openssl x509 -req -days 3650 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
        -CAcreateserial -out cert.pem -extfile extfile-client.cnf \
        || error_exit "签名客户端证书失败"

    # 清理临时文件
    print_info "清理临时文件..."
    cleanup

    # 设置权限
    print_info "设置文件权限..."
    chmod 0600 ca-key.pem server-key.pem key.pem || print_warning "设置私钥权限失败"
    chmod 0600 ca.pem server-cert.pem cert.pem || print_warning "设置证书权限失败"

    # 设置目录和文件所有者
    print_info "设置目录和文件所有者..."
    chown -R gitlab-runner:gitlab-runner /etc/gitlab-runner/certs 2>/dev/null || \
        print_warning "设置所有者失败，请手动执行: sudo chown -R gitlab-runner:gitlab-runner /etc/gitlab-runner/certs"
    chmod -R 700 /etc/gitlab-runner/certs || print_warning "设置目录权限失败"

    # 验证生成的文件
    echo ""
    print_info "验证生成的证书文件..."
    ls -lh *.pem

    echo ""
    echo "========================================"
    print_info "证书生成完成！"
    echo "========================================"
    echo ""
    echo "生成的证书文件："
    echo "  ca-key.pem       - CA 私钥"
    echo "  ca.pem           - CA 证书"
    echo "  server-key.pem  - 服务器私钥"
    echo "  server-cert.pem - 服务器证书"
    echo "  key.pem          - 客户端私钥"
    echo "  cert.pem         - 客户端证书"
    echo ""
    print_info "证书存储位置: $CERT_DIR"
    print_info "证书有效期: 10 年"
    echo ""
}

# 执行主函数
main "$@"
