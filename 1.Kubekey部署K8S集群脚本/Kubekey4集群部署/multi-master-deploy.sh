#!/bin/bash

# KubeKey 4.0.2 Kubernetes 多主节点集群部署脚本
# 仅在主机名为 master 时执行部署

set -e  # 遇到错误时退出

# ==================== 常量和配置 ====================

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# 集群配置
readonly CLUSTER_CONFIG_FILE="multi-master-config.yaml"
readonly KUBEKEY_BINARY="kubekey-linux-amd64"
readonly DEFAULT_K8S_VERSION="v1.34.2"

# 多节点配置
readonly MASTER_NODE="192.168.40.141"
readonly NODE1="192.168.40.142"
readonly NODE2="192.168.40.143"
readonly NODE_PASSWORD="2028"
readonly SSH_USER="root"

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
        
        if [[ "$PRETTY_NAME" != *"Ubuntu"* ]]; then
            log_warn "警告: 检测到的操作系统 $OS_NAME $OS_VERSION 可能不完全支持"
            log_warn "推荐使用 Ubuntu 系统"
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
    modules=("overlay" "br_netfilter")
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
    
    log_info "软件包安装完成"
}

# 配置防火墙（可选）
configure_firewall() {
    log_info "检查防火墙配置..."
    
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            log_info "检测到 UFW 防火墙已启用"
            
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
    
    if command -v timedatectl &> /dev/null; then
        if timedatectl status | grep -q "NTP active: yes"; then
            log_info "系统已有时间同步服务启用"
        else
            if systemctl enable systemd-timesyncd 2>/dev/null; then
                systemctl start systemd-timesyncd
                log_info "已启用 systemd-timesyncd 时间同步服务"
            elif command -v ntp &> /dev/null; then
                systemctl enable ntp
                systemctl start ntp
                log_info "已启用 NTP 时间同步服务"
            else
                log_warn "无法配置时间同步服务，可能需要手动配置"
            fi
        fi
    fi
    
    log_info "等待时间同步完成..."
    sleep 5
    
    log_info "当前时间: $(date)"
    log_info "时间同步配置完成"
}

# 配置 hostname
configure_hostname() {
    log_info "检查主机名配置..."
    
    local current_hostname=$(hostname)
    log_info "当前主机名: $current_hostname"
    
    if ! grep -q "$current_hostname" /etc/hosts; then
        local ip_address=$(hostname -I | awk '{print $1}')
        echo "$ip_address $current_hostname" >> /etc/hosts
        log_info "已添加主机名到 /etc/hosts"
    fi
}

# 配置 root SSH 登录
configure_root_ssh() {
    log_info "配置 root SSH 登录..."
    
    # 设置 root 密码
    if ! grep -q "^root:" /etc/shadow; then
        log_info "设置 root 密码..."
        echo "root:$NODE_PASSWORD" | chpasswd
    fi
    
    # 备份原始 SSH 配置
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # 启用 root 登录
    if grep -q "^#*PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi
    
    # 启用密码认证
    if grep -q "^#*PasswordAuthentication" /etc/ssh/sshd_config; then
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi
    
    # 重启 SSH 服务
    if systemctl restart sshd; then
        log_info "SSH 服务重启成功，root 登录已启用"
    else
        service ssh restart
        log_info "SSH 服务重启完成，root 登录已启用"
    fi
}

# 验证环境准备
verify_setup() {
    log_info "验证环境准备..."
    
    local errors=0
    
    if swapon --show | grep -q "NAME"; then
        log_error "错误: Swap 仍在启用状态"
        ((errors++))
    else
        log_info "✓ Swap 已禁用"
    fi
    
    for module in overlay br_netfilter; do
        if ! lsmod | grep -q "$module"; then
            log_error "错误: 内核模块 $module 未加载"
            ((errors++))
        else
            log_info "✓ 内核模块 $module 已加载"
        fi
    done
    
    local commands=("docker" "kubectl" "kubeadm" "kubelet")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_warn "警告: $cmd 未安装 (将在部署过程中安装)"
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
    export KKZONE=cn
    log_info "设置 KKZONE=cn，使用国内镜像源加速下载"
    log_info "开始下载 KubeKey 4.0.2..."

    local download_filename="kubekey-v4.0.2-linux-amd64.tar.gz"
    
    if [ -f "$download_filename" ]; then
        log_info "找到本地 KubeKey 压缩包，直接解压"
        cp "$download_filename" "$KUBEKEY_BINARY.tar.gz"
    else
        if [ -f "$KUBEKEY_BINARY" ]; then
            log_warn "KubeKey 已存在，跳过下载和解压"
            return
        fi
        
        local primary_url="https://github.com/kubesphere/kubekey/releases/download/v4.0.2/$download_filename"
            
        log_info "正在下载 KubeKey 4.0.2..."
            
        if ! curl -L -o "$download_filename" "$primary_url"; then
            log_error "无法下载 KubeKey，请检查网络连接"
            exit 1
        fi
            
        if [ ! -f "$download_filename" ]; then
            log_error "下载的文件不存在，请检查网络连接"
            exit 1
        fi
            
        mv "$download_filename" "$KUBEKEY_BINARY.tar.gz"
    fi

    if ! tar -zxf "$KUBEKEY_BINARY.tar.gz"; then
        log_error "解压 KubeKey 失败"
        exit 1
    fi

    local extracted_binary=$(find . -maxdepth 1 -name "kubekey-*" -type f -executable 2>/dev/null | head -n 1)
    
    if [ -n "$extracted_binary" ]; then
        if [ "$extracted_binary" != "$KUBEKEY_BINARY" ]; then
            if [ ! -f "$KUBEKEY_BINARY" ] || [ "$extracted_binary" != "./$KUBEKEY_BINARY" ]; then
                mv "$extracted_binary" "$KUBEKEY_BINARY"
            fi
        fi
    elif [ -f "kk" ]; then
        mv "kk" "$KUBEKEY_BINARY"
    elif [ ! -f "$KUBEKEY_BINARY" ]; then
        log_error "未找到 KubeKey 二进制文件"
        exit 1
    else
        log_info "KubeKey 二进制文件已存在: $KUBEKEY_BINARY"
    fi

    if ! chmod +x "$KUBEKEY_BINARY" ; then
        log_error "设置 KubeKey 执行权限失败"
        exit 1
    fi

    log_info "KubeKey 4.0.2 下载并解压成功"
}

# 生成多主节点配置文件
generate_multi_master_config() {
    local version=${1:-"v1.35.0"}
    
    log_info "生成多主节点集群配置文件..."
    
    mkdir -p $(dirname "$CLUSTER_CONFIG_FILE")
    
    cat > "$CLUSTER_CONFIG_FILE" << EOF
apiVersion: kubekey.io/v1alpha2
kind: Cluster
metadata:
  name: multi-master-cluster
spec:
  hosts:
  # 多主节点配置
  - name: master
    address: $MASTER_NODE
    internalAddress: $MASTER_NODE
    user: $SSH_USER
    password: "$NODE_PASSWORD"
    role: [master, etcd]
    arch: amd64
  
  - name: node1
    address: $NODE1
    internalAddress: $NODE1
    user: $SSH_USER
    password: "$NODE_PASSWORD"
    role: [worker]
    arch: amd64
  
  - name: node2
    address: $NODE2
    internalAddress: $NODE2
    user: $SSH_USER
    password: "$NODE_PASSWORD"
    role: [worker]
    arch: amd64

  roleGroups:
    etcd:
    - master
    control-plane:
    - master
    worker:
    - node1
    - node2

  controlPlaneEndpoint:
    domain: lb.kubesphere.local
    address: "$MASTER_NODE"
    port: "6443"

  kubernetes:
    version: $version
    clusterName: cluster.local
    autoRenewCerts: true
    enableAudit: true
    enableMetricsServer: true
    containerManager: docker
    corednsReplicaCount: 2
    masqueradeAll: false
    maxPods: 110

  etcd:
    type: kubekey

  network:
    plugin: calico
    calico:
      ipipMode: Always
      vethMTU: 1440
    kubePodsCIDR: 10.238.64.0/18
    kubeServiceCIDR: 10.239.64.0/18

  registry:
    plainHTTP: false
    privateRegistry: ""
  addons: []
EOF

    log_info "多主节点集群配置文件生成成功: $CLUSTER_CONFIG_FILE"
    log_info "配置文件内容预览:"
    head -20 "$CLUSTER_CONFIG_FILE"
}

# 验证节点连接
verify_nodes() {
    log_info "验证节点连接..."
    
    log_info "验证节点SSH连通性:"
    for node in $MASTER_NODE $NODE1 $NODE2; do
        log_info "测试连接到节点 $node..."
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $SSH_USER@$node "echo 'SSH连接成功'"; then
            log_info "✓ 节点 $node SSH 连接成功"
        else
            log_error "✗ 无法连接到节点 $node，请检查网络和SSH配置"
            exit 1
        fi
    done
    
    log_info "运行 KubeKey 预检查..."
    if ! ./$KUBEKEY_BINARY precheck --config "$CLUSTER_CONFIG_FILE"; then
        log_error "节点预检查失败，请检查错误信息"
        exit 1
    else
        log_info "✓ 节点预检查通过"
    fi
}

# 部署 Kubernetes 集群
deploy_cluster() {
    log_info "开始部署 Kubernetes 多主节点集群..."
    log_info "此过程可能需要 20-40 分钟，请耐心等待..."
    
    export KKZONE=cn
    log_info "设置 KKZONE=cn，确保Kubernetes组件从国内镜像源下载"
    
    if ! ./$KUBEKEY_BINARY create cluster --config "$CLUSTER_CONFIG_FILE"; then
        log_error "Kubernetes 集群部署失败"
        exit 1
    fi
    
    log_info "Kubernetes 多主节点集群部署成功！"
}

# 显示集群状态
show_cluster_status() {
    log_info "显示集群状态..."

    if command -v kubectl &> /dev/null; then
        log_info "Kubernetes 节点状态："
        kubectl get nodes -o wide
        
        log_info "Kubernetes 组件状态："
        kubectl get pods -n kube-system
        
        log_info "集群版本信息："
        kubectl version
    else
        log_warn "kubectl 未安装或不可用，无法显示集群状态"
    fi
}

# 显示部署后操作指南
show_post_deployment_guide() {
    cat << EOF
${GREEN}===========================================
部署完成！后续操作指南：
===========================================${NC}

1. ${YELLOW}验证集群状态：${NC}
   kubectl get nodes
   kubectl get pods -n kube-system -o wide

2. ${YELLOW}检查核心服务：${NC}
   kubectl get cs
   kubectl get deployments -n kube-system

3. ${YELLOW}集群网络检查：${NC}
   kubectl get svc
   kubectl describe nodes | grep -A 10 -B 10 "InternalIP"

4. ${YELLOW}节点角色信息：${NC}
   kubectl get nodes -o wide --show-labels | grep -E "NAME|role"

${GREEN}集群节点信息：${NC}
- 控制平面节点: ${MASTER_NODE} (master)
- 工作节点: ${NODE1} (node1), ${NODE2} (node2)

${GREEN}访问信息：${NC}
- Kubernetes API Server: https://${MASTER_NODE}:6443
- 所有节点SSH访问: root@节点IP (密码: ${NODE_PASSWORD})

${GREEN}更多信息请参考：${NC}
- KubeKey 文档: https://github.com/kubesphere/kubekey
- Kubernetes 文档: https://kubernetes.io/docs/
EOF
}

# ==================== 主函数 ====================

prepare_environment() {
    log_info "==========================================="
    log_info "KubeKey 4.0.2 Kubernetes 多主节点集群环境准备"
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
    log_info "KubeKey 4.0.2 Kubernetes 多主节点集群部署"
    log_info "控制平面节点: $MASTER_NODE"
    log_info "工作节点: $NODE1, $NODE2"
    log_info "SSH用户: $SSH_USER"
    log_info "当前时间: $(date)"
    log_info "==========================================="

    check_root
    check_dependencies
    generate_multi_master_config "$DEFAULT_K8S_VERSION"
    download_kubekey
    verify_nodes

    log_warn "在继续部署之前，请确认以下配置是否正确："
    log_warn "控制平面节点: $MASTER_NODE"
    log_warn "工作节点: $NODE1, $NODE2"
    log_warn "SSH密码: $NODE_PASSWORD"
    log_warn "K8s版本: $DEFAULT_K8S_VERSION"
    read -p "确认配置正确后按 Enter 继续部署，或按 Ctrl+C 取消... "

    deploy_cluster
    show_cluster_status
    show_post_deployment_guide

    log_info "==========================================="
    log_info "KubeKey 4.0.2 多主节点集群部署完成！"
    log_info "==========================================="
}

# 主执行流程
main() {
    # 执行环境准备（所有节点都需要）
    prepare_environment

    # 检查主机名是否为master，确保只在master节点执行部署
    local current_hostname=$(hostname)
    local current_ip=$(hostname -I | awk '{print $1}')
    
    log_info "当前主机名: $current_hostname"
    log_info "当前IP地址: $current_ip"
    
    if [ "$current_hostname" = "master" ] || [ "$current_ip" = "$MASTER_NODE" ]; then
        log_info "当前节点是master节点，继续执行Kubernetes部署..."
        # 执行Kubernetes部署
        deploy_kubernetes
    else
        log_info "当前节点不是master节点，仅完成环境准备"
        log_info "Kubernetes集群部署将在master节点($MASTER_NODE)上执行"
        log_info "当前节点环境已准备就绪，可用于加入Kubernetes集群"
    fi
}

# 启动主函数
main "$@"