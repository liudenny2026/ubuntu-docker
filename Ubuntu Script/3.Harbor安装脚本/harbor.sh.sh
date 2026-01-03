#!/bin/bash

########################1.准备文件###############################
#下载离线包
 
wget https://githubfast.com/goharbor/harbor/releases/download/v2.14.1/harbor-offline-installer-v2.14.1.tgz

tar -zxvf harbor-offline-installer-v2.14.1.tgz

cd harbor

#########################2.编辑文件##################################
# 编辑配置文件 vim harbor.yml

hostname: 192.168.40.249  # 使用 IP

# HTTPS配置（生产环境必需）
https:
  port: 443
  certificate: /data/cert/server.crt  # 证书文件路径
  private_key: /data/cert/server.key  # 私钥文件路径

##########################3.生成证书###################################

# 创建证书目录
sudo mkdir -p /data/cert

# 生成私钥
sudo openssl genrsa -out /data/cert/server.key 2048

# 生成证书请求和自签名证书
sudo openssl req -x509 -new -nodes -key server.key -sha256 -days 3650 -out server.crt -config openssl.cnf

# 验证证书是否包含SAN
sudo openssl x509 -in server.crt -text -noout | grep -A1 "Subject Alternative Name"

正确输出
  X509v3 Subject Alternative Name: 
                IP Address:192.168.40.249, DNS:harbor.local, DNS:myharbor.com

###########################4.安装#########################################
# 运行安装脚本
sudo ./install.sh

# 如果需要安装其他组件 
# sudo ./install.sh --with-trivy  
 
##################################5.配置 Docker 信任==关键########################
sudo mkdir -p /etc/docker/certs.d/harbor.local
sudo mkdir -p /etc/docker/certs.d/192.168.40.249

sudo cp /data/cert/server.crt /etc/docker/certs.d/harbor.local/ca.crt
sudo cp /data/cert/server.crt /etc/docker/certs.d/192.168.40.249/ca.crt

sudo systemctl restart docker

netstat -tuln | grep 443


#####################6.在Docker 客户端机器上###########################
echo "192.168.40.249 harbor.local" | sudo tee -a /etc/hosts

ping harbor.local

###################7.客户端添加证书到Docker信任库##############################
mkdir -p /etc/docker/certs.d/192.168.40.249:443

#1.将证书文件(ca.crt)复制到该目录，或使用以下命令获取
openssl s_client -showcerts -connect 192.168.40.249:443 </dev/null 2>/dev/null|openssl x509 -outform PEM > /etc/docker/certs.d/192.168.40.249:443/ca.crt

#2.或scp传输
scp ubuntu@192.168.40.249:/etc/docker/certs.d/192.168.40.249/ca.crt /etc/docker/certs.d/192.168.40.249\:443/

# 2. 重启Docker服务
systemctl restart docker

# 3. 重新登录
echo "User@12345" | docker login https://192.168.40.249 -u user --password-stdin



#####################################临时解决###################  
 # 编辑Docker daemon配置
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "insecure-registries": ["192.168.40.249"]
}
EOF

# 重启Docker
sudo systemctl restart docker

# 然后登录(不使用https)
docker login 192.168.40.249 -u user -p User@12345

###################推送镜像###############
# 格式: docker tag 本地镜像:标签 harbor地址/项目名/镜像名:标签
docker tag ollama-client:0.1.1 192.168.40.249/devsecops/ollama-client:0.1.1

docker push 192.168.40.249/devsecops/ollama-client:0.1.1


docker tag ollama-server:0.2.1 192.168.40.249/devsecops/ollama-server:0.2.1

docker push 192.168.40.249/devsecops/ollama-server:0.2.1


###########通过Harbor缓存代理拉取docker或harbor镜像一定加 /library/###############
镜像站点：https://docker.1ms.run

重要：
镜像拉取格式：192.168.40.249/mirror/library/镜像名:标签

# 如果已正确配置Docker和证书
docker pull 192.168.40.249/mirror/library/nginx:latest

# 或者使用临时方案（测试用）
docker --insecure-registry 192.168.40.249 pull 192.168.40.249/mirror/library/nginx:latest


##################Harbor私有镜像站点#####################
docker pull/push 192.168.40.249/devsecops/ollama-server:0.2.1


###############################################################33
推送正确的 ArgoCD 镜像到私有仓库ArgoCD 的官方镜像通常来自 quay.io/argoproj/argocd。
您需要：从官方仓库拉取镜像重新标记并推送到您的私有仓库
bash
# Pull official ArgoCD images
docker pull quay.io/argoproj/argocd:v2.3.3

# Tag for your private registry
docker tag quay.io/argoproj/argocd:v2.3.3 192.168.40.249/mirror/library/argocd:v2.3.3

docker tag quay.io/argoproj/argocd:v2.3.3 192.168.40.249/mirror/library/argocd:latest


# Push to your private registry
docker push 192.168.40.249/mirror/library/argocd:v2.3.3

docker push 192.168.40.249/mirror/library/argocd:latest