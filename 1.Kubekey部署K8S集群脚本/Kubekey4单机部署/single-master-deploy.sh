#!/bin/bash

# KubeKey 4.0.2 Kubernetes 集群统一部署脚本

# 新增主机名判断逻辑 - 仅在主机名为 master 时执行部署

set -e  # 遇到错误时退出

# ==================== 常量和配置 ====================

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# 集群配置
readonly CLUSTER_CONFIG_FILE="cluster-config.yaml"
readonly KUBEKEY_BINARY="kubekey-linux-amd64"
readonly DEFAULT_K8S_VERSION="v1.35.0"

# 默认单节点配置
readonly DEFAULT_SINGLE_NODE_IP="192.168.2.240"
readonly DEFAULT_PASSWORD="2026"

# ==================== 日志函数 ====================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==================== 准备阶段函数 ====================

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_info "脚本以 root 权限运行"
    else
        log_error "此脚本需要 root 权限运行，请使用 sudo 或以 root 用户身份运行"
        exit 1
    fi
}

# 检查操作系统
check_os() {
    log_info "检查操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
        
        log_info "检测到操作系统: $OS_NAME $OS_VERSION"
        
        # 检查是否为支持的操作系统
        local supported=0
        for os in "${SUPPORTED_OS[@]}"; do
            if [[ "$PRETTY_NAME" == *"$os"* ]]; then
                supported=1
                break
            fi
        done
        
        if [[ $supported -eq 0 ]]; then
            log_warn "警告: 检测到的操作系统 $OS_NAME $OS_VERSION 可能不受完全支持"
            log_warn "支持的操作系统: ${SUPPORTED_OS[*]}"
            log_warn "继续执行可能会有问题"
        else
            log_info "操作系统受支持"
        fi
    else
        log_error "无法确定操作系统信息"
        exit 1
    fi
}

# 检查系统资源
check_resources() {
    log_info "检查系统资源..."
    
    # 检查内存
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -lt 2 ]; then
        log_warn "警告: 系统内存少于 2GB，Kubernetes 推荐至少 2GB"
    else
        log_info "内存: ${mem_gb}GB (满足要求)"
    fi
    
    # 检查磁盘空间
    local disk_gb=$(df -h / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_gb" -lt 20 ]; then
        log_warn "警告: 可用磁盘空间少于 20GB，建议至少 20GB"
    else
        log_info "可用磁盘空间: ${disk_gb}GB (满足要求)"
    fi
}

# 禁用 swap
disable_swap() {
    log_info "禁用 swap..."
    
    # 临时禁用
    swapoff -a
    
    # 永久禁用 - 注释掉 /etc/fstab 中的 swap 行
    sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    log_info "swap 已禁用"
}

# 配置内核模块
setup_kernel_modules() {
    log_info "配置内核模块..."
    
    # 加载必要模块
    local modules=("overlay" "br_netfilter")
    for module in "${modules[@]}"; do
        if ! lsmod | grep -q "$module"; then
            modprobe "$module"
            log_info "已加载模块: $module"
        else
            log_info "模块 $module 已加载"
        fi
    done
    
    # 永久加载模块
    cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    
    log_info "内核模块配置完成"
}

# 配置系统参数
setup_sysctl() {
    log_info "配置系统参数..."
    
    # 配置内核参数
    cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.swappiness                       = 0
fs.file-max                         = 100000
EOF
    
    # 应用配置
    sysctl --system
    
    log_info "系统参数配置完成"
}

# 安装必要软件包
install_packages() {
    log_info "更新包列表并安装必要软件包..."
    
    apt-get update
    
    # 安装必要软件包
    local packages=(
        "curl"
        "wget"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "socat"
        "conntrack"
        "ebtables"
        "ipset"
        "iptables"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "安装软件包: $package"
            apt-get install -y "$package"
        else
            log_info "软件包 $package 已安装"
        fi
    done
    
    # 尝试安装时间同步服务，但不强制安装以避免冲突
    if ! dpkg -l | grep -q "^ii  ntp \|^ii  chrony \|^ii  systemd-timesyncd "; then
        log_info "尝试安装时间同步服务..."
        # 优先安装 systemd-timesyncd（通常已预装）
        if ! systemctl enable systemd-timesyncd 2>/dev/null; then
            # 如果失败，尝试安装 ntp
            if ! apt-get install -y ntp 2>/dev/null; then
                log_warn "无法安装时间同步服务，可能已存在其他时间同步服务"
            fi
        fi
    else
        log_info "时间同步服务已安装"
    fi
    
    log_info "软件包安装完成"
}

# 配置防火墙（可选）
configure_firewall() {
    log_info "检查防火墙配置..."
    
    if command -v ufw &> /dev/null; then
        # 检查 UFW 是否已启用
        if ufw status | grep -q "Status: active"; then
            log_info "检测到 UFW 防火墙已启用"
            
            # Kubernetes 需要的端口
            local ports=(
                "6443"    # Kubernetes API server
                "2379-2380" # etcd server client API
                "10250"   # Kubelet
                "10251"   # kube-scheduler
                "10252"   # kube-controller-manager
                "30000-32767" # NodePort Services
            )
            
            for port in "${ports[@]}"; do
                ufw allow "$port" || true
            done
            
            log_info "已为 Kubernetes 配置 UFW 防火墙规则"
        else
            log_info "UFW 防火墙已安装但未启用，跳过配置"
        fi
    else
        log_info "UFW 防火墙未安装，跳过配置"
    fi
}

# 时间同步配置
configure_time_sync() {
    log_info "配置时间同步..."
    
    # 检查并配置时间同步服务
    if command -v timedatectl &> /dev/null; then
        # 检查是否已有时间同步服务启用
        if timedatectl status | grep -q "NTP active: yes"; then
            log_info "系统已有时间同步服务启用"
        else
            # 尝试启用 systemd-timesyncd（优先使用系统自带服务）
            if systemctl enable systemd-timesyncd 2>/dev/null; then
                systemctl start systemd-timesyncd
                log_info "已启用 systemd-timesyncd 时间同步服务"
            elif command -v ntp &> /dev/null; then
                # 如果 ntp 可用则启用
                systemctl enable ntp
                systemctl start ntp
                log_info "已启用 NTP 时间同步服务"
            else
                log_warn "无法配置时间同步服务，可能需要手动配置"
            fi
        fi
    fi
    
    # 等待时间同步
    log_info "等待时间同步完成..."
    sleep 5
    
    log_info "当前时间: $(date)"
    log_info "时间同步配置完成"
    
    # 显示时间同步状态
    if command -v timedatectl &> /dev/null; then
        log_info "时间同步状态: $(timedatectl status | grep "NTP active:" || echo "无法获取时间同步状态")"
    fi
}

# 配置 hostname（如果需要）
configure_hostname() {
    log_info "检查主机名配置..."
    
    local current_hostname=$(hostname)
    log_info "当前主机名: $current_hostname"
    
    # 检查 /etc/hosts 文件中是否有主机名解析
    if ! grep -q "$current_hostname" /etc/hosts; then
        local ip_address=$(hostname -I | awk '{print $1}')
        echo "$ip_address $current_hostname" >> /etc/hosts
        log_info "已添加主机名到 /etc/hosts"
    fi
}

# 配置 root SSH 登录
configure_root_ssh() {
    log_info "配置 root SSH 登录..."
    
    # 1. 设置 root 密码（如果尚未设置）
    if ! grep -q "^root:" /etc/shadow; then
        log_info "设置 root 密码..."
        echo "root:2026" | chpasswd
    fi
    
    # 2. 备份原始 SSH 配置
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # 3. 启用 root 登录
    if grep -q "^#*PermitRootLogin" /etc/ssh/sshd_config; then
        # 已存在配置，修改为允许
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        # 不存在配置，添加新配置
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi
    
    # 4. 启用密码认证
    if grep -q "^#*PasswordAuthentication" /etc/ssh/sshd_config; then
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi
    
    # 5. 重启 SSH 服务
    if systemctl restart sshd; then
        log_info "SSH 服务重启成功，root 登录已启用"
    else
        service ssh restart
        log_info "SSH 服务重启完成，root 登录已启用"
    fi
    
    # 6. 验证配置
    if ssh -o StrictHostKeyChecking=no root@localhost "echo 'root SSH登录测试成功'"; then
        log_info "✓ root SSH 登录配置成功"
    else
        log_warn "root SSH 登录测试失败，请手动检查"
    fi
}

# 验证环境准备
verify_setup() {
    log_info "验证环境准备..."
    
    local errors=0
    
    # 验证 swap 是否已禁用
    if swapon --show | grep -q "NAME"; then
        log_error "错误: Swap 仍在启用状态"
        ((errors++))
    else
        log_info "✓ Swap 已禁用"
    fi
    
    # 验证内核模块
    for module in overlay br_netfilter; do
        if ! lsmod | grep -q "$module"; then
            log_error "错误: 内核模块 $module 未加载"
            ((errors++))
        else
            log_info "✓ 内核模块 $module 已加载"
        fi
    done
    
    # 验证必要命令
    local commands=("docker" "kubectl" "kubeadm" "kubelet")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_warn "警告: $cmd 未安装 (这可能是正常的，将在部署过程中安装)"
        else
            log_info "✓ $cmd 已安装"
        fi
    done
    
    if [ $errors -eq 0 ]; then
        log_info "环境验证通过"
    else
        log_error "环境验证发现问题，共 $errors 个错误"
        return 1
    fi
}

# ==================== 部署阶段函数 ====================

# 显示使用说明
show_usage() {
    cat << EOF
使用方法: $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -s, --single            单节点部署模式 (默认)
    -m, --multi             多节点部署模式
    -i, --ip IP             指定单节点IP地址 (默认: $DEFAULT_SINGLE_NODE_IP)
    -p, --password PASS     指定节点密码 (默认: $DEFAULT_PASSWORD)
    -v, --version VERSION   指定K8s版本 (默认: $DEFAULT_K8S_VERSION)
    --dry-run               仅显示配置，不执行部署
    --validate-only         仅验证配置和依赖，不执行部署

示例:
    $0                              # 单节点部署 (使用默认配置)
    $0 -s                           # 单节点部署
    $0 -m                           # 多节点部署 (使用现有配置文件)
    $0 -s -i 192.168.1.100 -p mypass    # 指定IP和密码的单节点部署
EOF
}

# 解析命令行参数
parse_args() {
    DEPLOY_MODE="single"          # 默认单节点模式
    TARGET_IP="$DEFAULT_SINGLE_NODE_IP"
    NODE_PASSWORD="$DEFAULT_PASSWORD"
    K8S_VERSION="$DEFAULT_K8S_VERSION"
    DRY_RUN=false
    VALIDATE_ONLY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--single)
                DEPLOY_MODE="single"
                shift
                ;;
            -m|--multi)
                DEPLOY_MODE="multi"
                shift
                ;;
            -i|--ip)
                TARGET_IP="$2"
                shift 2
                ;;
            -p|--password)
                NODE_PASSWORD="$2"
                shift 2
                ;;
            -v|--version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 检查依赖
declare -a REQUIRED_COMMANDS=("curl" "tar" "sudo" "openssl")

check_dependencies() {
    log_info "检查系统依赖..."

    local missing_deps=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "以下必需的命令未找到: ${missing_deps[*]}"
        log_error "请先安装缺失的依赖包"
        exit 1
    fi

    log_info "所有依赖检查通过"
}

# 下载 KubeKey 4.0.2
download_kubekey() {
    # 设置国内下载区域，加速下载
    export KKZONE=cn
    log_info "设置 KKZONE=cn，使用国内镜像源加速下载"
    log_info "开始下载 KubeKey 4.0.2..."

    local download_filename="kubekey-v4.0.2-linux-amd64.tar.gz"
    
    # 检查是否已存在压缩包文件
    if [ -f "$download_filename" ]; then
        log_info "找到本地 KubeKey 压缩包: $download_filename，跳过下载，直接解压"
        # 重命名本地文件为预期的文件名
        cp "$download_filename" "$KUBEKEY_BINARY.tar.gz"
    else
        # 检查是否已存在解压后的 kubekey 二进制文件
        if [ -f "$KUBEKEY_BINARY" ]; then
            log_warn "KubeKey 已存在，跳过下载和解压"
            return
        fi
        
        local primary_url="https://githubfast.com/kubesphere/kubekey/releases/download/v4.0.2/$download_filename"
            
        log_info "正在下载 KubeKey 4.0.2..."
            
        if ! curl -L -o "$download_filename" "$primary_url"; then
            log_error "无法下载 KubeKey，请检查网络连接"
            exit 1
        fi
            
        # 检查下载的文件是否存在
        if [ ! -f "$download_filename" ]; then
            log_error "下载的文件不存在，请检查网络连接"
            exit 1
        fi
            
        # 重命名下载的文件为预期的文件名
        mv "$download_filename" "$KUBEKEY_BINARY.tar.gz"
    fi

    # 解压
    if ! tar -zxf "$KUBEKEY_BINARY.tar.gz"; then
        log_error "解压 KubeKey 失败"
        exit 1
    fi

    # 查找解压出来的 KubeKey 二进制文件
    local extracted_binary=$(find . -maxdepth 1 -name "kubekey-*" -type f -executable 2>/dev/null | head -n 1)
    
    if [ -n "$extracted_binary" ]; then
        # 如果找到了匹配的文件，将其重命名为期望的文件名
        if [ "$extracted_binary" != "$KUBEKEY_BINARY" ]; then
            # 避免源文件和目标文件相同的情况
            if [ ! -f "$KUBEKEY_BINARY" ] || [ "$extracted_binary" != "./$KUBEKEY_BINARY" ]; then
                mv "$extracted_binary" "$KUBEKEY_BINARY"
            fi
        fi
    elif [ -f "kk" ]; then
        # 如果解压出来的是 kk 文件（KubeKey 的常见名称）
        mv "kk" "$KUBEKEY_BINARY"
    elif [ ! -f "$KUBEKEY_BINARY" ]; then
        # 如果以上条件都不满足且目标文件不存在，则报错
        log_error "未找到 KubeKey 二进制文件"
        exit 1
    else
        # 目标文件已存在
        log_info "KubeKey 二进制文件已存在: $KUBEKEY_BINARY"
    fi

    # 设置执行权限
    if ! chmod +x "$KUBEKEY_BINARY" ; then
        log_error "设置 KubeKey 执行权限失败"
        exit 1
    fi

    log_info "KubeKey 4.0.2 下载并解压成功"
}

# 生成单节点配置文件
generate_single_node_config() {
    local ip=$1
    local password=$2
    local version=$3
    
    # 如果未指定IP，则自动获取当前节点IP
    if [ -z "$ip" ] || [ "$ip" == "auto" ]; then
        ip=$(hostname -I | awk '{print $1}')
        log_info "自动检测到当前节点IP: $ip"
    fi
    
    log_info "生成单节点集群配置文件..."
    
    # 确保配置目录存在
    mkdir -p $(dirname "$CLUSTER_CONFIG_FILE")
    
    cat > "$CLUSTER_CONFIG_FILE" << EOF
apiVersion: kubekey.io/v1alpha2
kind: Cluster
metadata:
  name: sample
spec:
  hosts:
  # 单节点 Kubernetes 集群 - 同时担任控制平面和 etcd 角色
  - name: master
    address: $ip  # Ubuntu 24.04
    internalAddress: $ip  # Ubuntu 24.04
    user: root
    password: "$password"  # 请根据实际环境修改密码
    role: [master, etcd, worker]
    arch: amd64
  roleGroups:
    etcd:
    - master
    control-plane:
    - master
    worker:
    - master
  controlPlaneEndpoint:
    domain: lb.kubesphere.local
    address: "$ip"  # 使用主节点 IP
    port: "6443"
  kubernetes:
    version: $version  # 使用指定版本
    clusterName: cluster.local
    autoRenewCerts: true
    enableAudit: true
    enableMetricsServer: true
    containerManager: docker
    corednsReplicaCount: 1  # 单节点集群设置为1
    masqueradeAll: false
    maxPods: 110
  etcd:
    type: kubekey
  network:
    plugin: calico
    calico:
      ipipMode: Always
      vethMTU: 1440
    kubePodsCIDR: 10.233.64.0/18
    kubeServiceCIDR: 10.233.0.0/18
  registry:
    plainHTTP: false
    privateRegistry: ""
  addons: []
EOF

    log_info "单节点集群配置文件生成成功: $CLUSTER_CONFIG_FILE"
    log_info "配置文件内容预览:"
    head -20 "$CLUSTER_CONFIG_FILE"
}

# 验证节点连接
verify_nodes() {
    log_info "验证节点连接..."

    # 检查 SSH 连接
    if [ "$DEPLOY_MODE" = "single" ]; then
        log_info "请确保主节点 ($TARGET_IP) 可以通过 SSH 访问"
    else
        log_info "请确保所有节点可以通过 SSH 访问"
    fi
    
    log_info "运行 '$KUBEKEY_BINARY precheck --config $CLUSTER_CONFIG_FILE' 验证节点配置"
    
    # 执行 precheck 验证
    if ! ./$KUBEKEY_BINARY precheck --config "$CLUSTER_CONFIG_FILE"; then
        log_error "节点预检查失败，请检查错误信息"
        exit 1
    else
        log_info "✓ 节点预检查通过"
    fi
}

# 部署 Kubernetes 集群
deploy_cluster() {
    log_info "开始部署 Kubernetes 集群..."
    log_info "此过程可能需要 15-30 分钟，请耐心等待..."
    
    # 确保使用国内镜像源下载Kubernetes组件
    export KKZONE=cn
    log_info "设置 KKZONE=cn，确保Kubernetes组件从国内镜像源下载"
    
    # 执行集群部署 - KubeKey 4.x 版本不再使用 --yes 参数
    if ! ./$KUBEKEY_BINARY create cluster --config "$CLUSTER_CONFIG_FILE"; then
        log_error "Kubernetes 集群部署失败"
        exit 1
    fi
    
    log_info "Kubernetes 集群部署成功！"
    log_info "集群信息："
    kubectl get nodes -o wide
}

# 显示集群状态
show_cluster_status() {
    log_info "显示集群状态..."

    if command -v kubectl &> /dev/null; then
        log_info "Kubernetes 节点状态："
        kubectl get nodes -o wide
        
        log_info "Kubernetes 组件状态："
        kubectl get pods -n kube-system
    else
        log_warn "kubectl 未安装或不可用，无法显示集群状态"
    fi
}

# 配置单节点特定设置
configure_single_node() {
    log_info "配置单节点集群特定设置..."
    
    # 对于单节点集群，我们通常需要移除污点以便在主节点上调度pod
    log_info "如果需要允许在主节点上运行应用 pod，请运行以下命令移除污点："
    log_info "kubectl taint nodes --all node-role.kubernetes.io/control-plane-"
    log_info "kubectl taint nodes --all node-role.kubernetes.io/master-"
}

# 显示部署后操作指南
show_post_deployment_guide() {
    log_info "==========================================="
    log_info "部署完成！后续操作指南："
    log_info "==========================================="
    log_info "1. 验证集群状态："
    log_info "   kubectl get nodes"
    log_info "   kubectl get pods -n kube-system"
    log_info ""
    log_info "2. 对于单节点集群，移除污点以允许调度应用："
    log_info "   kubectl taint nodes --all node-role.kubernetes.io/control-plane-"
    log_info "   kubectl taint nodes --all node-role.kubernetes.io/master-"
    log_info ""
    log_info "3. 检查核心服务状态："
    log_info "   kubectl get cs"
    log_info ""
    log_info "更多信息请参考官方文档："
    log_info "- KubeKey 项目：https://github.com/kubesphere/kubekey"
    log_info "- Kubernetes 文档：https://kubernetes.io/docs/"
    log_info "- KubeSphere 官网：https://kubesphere.io/"
}

# ==================== 主函数 ====================

prepare_environment() {
    log_info "==========================================="
    log_info "KubeKey 4.0.2 Kubernetes 集群环境准备工具"
    log_info "准备 Ubuntu 系统以部署 Kubernetes 集群"
    log_info "当前时间: $(date)"
    log_info "==========================================="
    
    check_root
    check_os
    check_resources
    disable_swap
    setup_kernel_modules
    setup_sysctl
    install_packages
    configure_firewall
    configure_time_sync
    configure_hostname
    configure_root_ssh
    verify_setup
    
    log_info "==========================================="
    log_info "环境准备完成！"
    log_info "==========================================="
}

deploy_kubernetes() {
    log_info "==========================================="
    log_info "KubeKey 4.0.2 Kubernetes 集群统一部署工具"
    log_info "部署模式: $DEPLOY_MODE"
    log_info "当前时间: $(date)"
    log_info "==========================================="

    check_root
    check_dependencies

    if [ "$DEPLOY_MODE" = "single" ]; then
        log_info "使用单节点部署模式"
        log_info "目标节点: $TARGET_IP"
        log_info "K8s 版本: $K8S_VERSION"
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN 模式 - 将生成以下配置："
            log_info "  IP: $TARGET_IP"
            log_info "  密码: $NODE_PASSWORD"
            log_info "  版本: $K8S_VERSION"
            generate_single_node_config "$TARGET_IP" "$NODE_PASSWORD" "$K8S_VERSION"
            log_info "配置已生成，部署未执行"
            return 0
        fi
        
        generate_single_node_config "$TARGET_IP" "$NODE_PASSWORD" "$K8S_VERSION"
    else
        log_info "使用多节点部署模式"
        if [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
            log_error "配置文件 $CLUSTER_CONFIG_FILE 不存在，请先创建或使用单节点模式"
            exit 1
        fi
    fi

    download_kubekey
    verify_nodes

    if [ "$VALIDATE_ONLY" = true ]; then
        log_info "验证完成，退出（--validate-only 模式）"
        return 0
    fi

    log_warn "在继续部署之前，请检查 $CLUSTER_CONFIG_FILE 文件中的配置是否正确"
    if [ "$DEPLOY_MODE" = "single" ]; then
        log_warn "确保 $TARGET_IP 节点可以通过 SSH 访问 (使用 root 用户和密码)"
    fi
    read -p "确认配置正确后按 Enter 继续部署，或按 Ctrl+C 取消... "

    deploy_cluster

    if [ "$DEPLOY_MODE" = "single" ]; then
        configure_single_node
    fi

    show_cluster_status
    show_post_deployment_guide

    log_info "==========================================="
    log_info "KubeKey 4.0.2 Kubernetes 集群部署完成！"
    log_info "==========================================="
}

# 主执行流程
main() {
    # 1. 执行环境准备
    prepare_environment

    # 2. 检查主机名是否为master
    local current_hostname=$(hostname)
    if [ "$current_hostname" != "master" ]; then
        log_error "当前主机名不是'master'，退出部署流程"
        exit 0
    fi

    # 3. 解析命令行参数
    parse_args "$@"

    # 4. 执行Kubernetes部署
    deploy_kubernetes
}

# 启动主函数
main "$@"