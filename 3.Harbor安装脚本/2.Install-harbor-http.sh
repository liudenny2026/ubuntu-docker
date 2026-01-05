#!/bin/bash

######################### 配置变量 ###########################
HARBOR_IP="192.168.40.248"  # Harbor服务IP地址
HARBOR_VERSION="v2.14.1"    # Harbor版本
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

######################### 前置检查 ###########################
# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本或以 root 用户身份运行"
    exit 1
fi

# 检查必要的命令是否存在
for cmd in wget tar; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "错误：未找到命令 $cmd，请先安装"
        exit 1
    fi
done

######################### 1.准备文件 ###########################
echo "===== 1. 准备Harbor离线包 ====="

# 进入脚本目录
cd "$SCRIPT_DIR" || exit 1

# 检查是否已下载
if [ -f "harbor-offline-installer-${HARBOR_VERSION}.tgz" ]; then
    echo "离线包已存在，跳过下载"
else
    echo "正在下载Harbor离线包..."
    wget https://githubfast.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz
    if [ $? -ne 0 ]; then
        echo "错误：下载Harbor离线包失败"
        exit 1
    fi
fi

# 解压离线包
echo "正在解压Harbor离线包..."
if [ -d "harbor" ]; then
    echo "harbor 目录已存在，跳过解压"
else
    tar -zxvf harbor-offline-installer-${HARBOR_VERSION}.tgz
    if [ $? -ne 0 ]; then
        echo "错误：解压失败"
        exit 1
    fi
fi

cd harbor || exit 1

######################### 2.编辑配置文件 ###########################
echo "===== 2. 配置Harbor (HTTP模式) ====="

# 备份原配置文件
cp harbor.yml.tmpl harbor.yml.bak

# 编辑harbor.yml配置文件
echo "正在配置harbor.yml..."
cat > harbor.yml << EOF
# Configuration file of Harbor

# The IP address or hostname to access admin UI and registry service.
# DO NOT use localhost, 127.0.0.1, or 0.0.0.0 as the hostname.
hostname: $HARBOR_IP

# http related config
http:
  # port for http, default is 80. If https enabled, this port will redirect to https port
  port: 80

# https related config
#https:
#  # https port for harbor, default is 443
#  port: 443
#  # The path of cert and key files for nginx
#  certificate: $CERT_DIR/server.crt
#  private_key: $CERT_DIR/server.key

# # Uncomment following will enable tls communication between all harbor components
# internal_tls:
#   enabled: true
#   # put the cert and key files under directory or secret with the name
#   # specified by the "internal_tls" existing in the storage_service of
#   # harbor.yml. Refer to enable_internal_tls.sh for more details.
#   dir: /etc/harbor/tls/internal

# Uncomment external_url if you want to enable external proxy
# And when it enabled the hostname will no longer used
# external_url: https://reg.mydomain.com:8433

# The initial password of Harbor admin
# It only works in first time to install harbor
# Change It after first time login
# The default username/password are admin/Harbor12345
harbor_admin_password: Harbor12345

# Harbor DB configuration
database:
  # The password for the root user of Harbor DB. Change this before any production use.
  password: root123
  # The maximum number of connections in the idle connection pool. If it <=0, no idle connections are retained.
  max_idle_conns: 100
  # The maximum number of open connections to the database. If it <= 0, then there is no limit on the number of open connections.
  # Note: the default number of connections is 1024 for postgres.
  max_open_conns: 900

# The default data volume
data_volume: /data/harbor

# Harbor Storage settings
storage:
  # By default, Harbor stores data on the local filesystem.
  # If you want to use external storage, uncomment this block and configure the settings accordingly.
  # More information about external storage configuration can be found at:
  # https://goharbor.io/docs/2.13.0/install-config/configure-storage-service/
  filesystem:
    maxthreads: 100

# Trivy configuration
# https://aquasecurity.github.io/trivy/v0.18/devdocs/configuration/config/#scanners
trivy:
  # ignoreUnfixed The flag to display only fixed vulnerabilities
  ignore_unfixed: false
  # skipUpdate The flag to enable or disable Trivy DB downloads
  # You may want to enable this flag in test or CI/CD environments to avoid downloading vulnerability DB.
  skip_update: false
  # offlineScan The flag to enable or disable offline scan
  offline_scan: false
  # securityCheck The security check to be performed
  # Available options are "vuln", "config", and "license". Comma-separated values are accepted.
  security_check: vuln,config
  # insecure The flag to skip verifying TLS certificates when downloading Trivy DB
  insecure: false
  # timeout The duration to wait before canceling the analysis
  timeout: 5m

jobservice:
  # Maximum number of job workers in job service
  max_job_workers: 10
  # The job service logger
  logger:
    # Job service log level. Options are debug, info, warning, error, fatal
    level: info
  # Loggers for the job service
  job_loggers:
    - name: FILE
      level: INFO
      rotate_count: 10
      rotate_size: 100M
      parameters:
        path: /var/log/jobservice
  # The duration of the logger sweeper in hours
  logger_sweeper_duration: 1

# Log configuration
log:
  # options are debug, info, warning, error, fatal
  level: info
  # configs for logs in local storage
  local:
    # Log files are rotated log_rotate_count times before being removed.
    rotate_count: 50
    # Log files are rotated only if they grow bigger than log_rotate_size bytes.
    rotate_size: 200M
    # The directory on your host that store log
    location: /var/log/harbor

# Notification configurations
notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3s
  event_endpoint: /api/v2.0/events
  event_consumer_topic: /topic/tasks
  event_consumer_pool_size: 5
  event_consumer_workers: 1

_version: 2.14.0

# Uncomment external_proxy if you want to use external proxy
# When external_proxy enabled, the user will access the Harbor via the specified proxy
# external_proxy:
#   http_proxy:
#   https_proxy:
#   no_proxy:
#   components:
#     - core
#     - jobservice
#     - trivy

# UAA Authentication Options
# If you want to use UAA for OIDC authentication, you should enable this and configure the options.
# uaa:
#   trustedIssuers: ""
#   keyCheckCacheTTL: 0h5m0s
EOF

if [ $? -ne 0 ]; then
    echo "错误：配置文件生成失败"
    exit 1
fi

echo "harbor.yml 配置完成"

######################### 3.安装Harbor ###########################
echo "===== 3. 开始安装Harbor ====="

# 运行安装脚本
echo "正在运行Harbor安装脚本..."
./install.sh --with-trivy

if [ $? -eq 0 ]; then
    echo ""
    echo "===== Harbor安装成功! ====="
    echo "访问地址: http://$HARBOR_IP"
    echo "默认用户名: admin"
    echo "默认密码: Harbor12345"
    echo ""
    echo "注意: Harbor使用HTTP模式运行，不配置SSL证书。"
else
    echo "错误：Harbor安装失败"
    exit 1
fi
