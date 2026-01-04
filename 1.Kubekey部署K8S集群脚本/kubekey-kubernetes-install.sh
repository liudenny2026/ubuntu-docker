#!/usr/bin/env bash

echo "开始系统环境准备..."

# 关闭防火墙
echo "关闭防火墙..."
sudo ufw disable

# 禁用交换分区
echo "禁用交换分区..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 加载内核模块
echo "加载内核模块..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 配置sysctl参数
echo "配置sysctl参数..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 更新系统并安装基础依赖
echo "更新系统并安装基础依赖..."
sudo apt update
sudo apt install -y curl wget socat conntrack ebtables ipset apt-transport-https ca-certificates gnupg lsb-release ipvsadm net-tools

# 设置时区为上海
echo "设置时区为上海..."
sudo timedatectl set-timezone Asia/Shanghai

#配置主机名解析
echo "配置主机名解析..."
sudo sed -i '$a 192.168.40.241 master' /etc/hosts
sudo sed -i '$a 192.168.40.242 node1' /etc/hosts
sudo sed -i '$a 192.168.40.243 node2' /etc/hosts
sudo sed -i '$a 192.168.40.249 server' /etc/hosts

#开启root登录
echo "开启root登录..."
sudo sed -i '/^#*PermitRootLogin/d' /etc/ssh/sshd_config
echo "PermitRootLogin yes" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh

#验证解析
echo "验证主机名解析..."
ping master -c 3
ping node1 -c 3
ping node2 -c 3
ping server -c 3



echo "系统环境准备完成，开始K8s集群部署..."

# 检查主机名是否等于master
if [ "$(hostname)" != "master" ]; then
    echo "错误：当前主机名 '$(hostname)' 不是Master节点"
    echo "此脚本只能在主master节点上执行"
    exit 1
fi

echo "当前主机名: $(hostname)，验证通过，继续执行..."


# 创建目录并进入
mkdir -p kubekey
cd kubekey
echo "已创建并进入kubekey目录"

# 设置环境变量
export KKZONE=cn
echo "已设置KKZONE=cn"

# 下载kubekey
echo "正在下载kubekey..."
wget https://githubfast.com/kubesphere/kubekey/releases/download/v3.1.11/kubekey-v3.1.11-linux-amd64.tar.gz

# 解压文件
echo "正在解压文件..."
tar -zxf kubekey-v3.1.11-linux-amd64.tar.gz

# 设置执行权限
echo "设置kk文件执行权限..."
chmod +x kk

# 创建config.yaml配置文件
echo "创建config.yaml配置文件..."
cat > config.yaml << 'EOF'
apiVersion: kubekey.kubesphere.io/v1alpha2
kind: Cluster
metadata:
  name: local.kubernetes.cluster
spec:
  hosts:  		 
  - {name: master, address: 192.168.40.241,  user: root, password: "2028"}
  - {name: node1, address: 192.168.40.242,  user: root, password: "2028"}
  - {name: node2, address: 192.168.40.243,  user: root, password: "2028"}
  roleGroups:							 
    etcd:
    - master
    control-plane: 
    - master
    worker:
    - node1
    - node2
  controlPlaneEndpoint:
    domain: local.kubernetes.cluster
    address: ""
    port: 6443
  kubernetes:
    version: v1.33.3
    clusterName: kubekey.kubernetes.cluster
    autoRenewCerts: true
    containerManager: docker
  etcd:
    type: kubekey
  network:
    plugin: calico
    kubePodsCIDR: 10.89.0.0/16		 
    kubeServiceCIDR: 10.64.0.0/16			
    multusCNI:
      enabled: false
  registry:
    privateRegistry: ""
    namespaceOverride: ""
    registryMirrors: []
    insecureRegistries: []
  addons: []
EOF

echo "config.yaml配置文件已创建"

# 再次设置环境变量并创建集群
echo "开始创建K8s集群..."
export KKZONE=cn
./kk create cluster -f config.yaml -y

echo "K8s集群部署完成！"
