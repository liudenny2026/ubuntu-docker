# 单阶段构建 - 简化版用于学习 Kaniko
FROM 192.168.40.248/library/ubuntu:24.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 使用阿里云镜像源加速
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's@//.*security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list.d/ubuntu.sources

# 安装小型工具和学习用软件
RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    vim \
    net-tools \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# 创建简单的静态页面
RUN echo '<!DOCTYPE html><html><head><title>Kaniko Demo</title></head>\
<body><h1>Hello from Kaniko!</h1>\
<p>这是一个使用 Kaniko 构建的简单 Nginx 镜像示例。看到此页面表明镜像构建成功</p>\
<p>Base Image: 192.168.40.248/library/ubuntu:24.04</p>\
</body></html>' > /var/www/html/index.html

# 复制配置文件（如果有）
# COPY nginx.conf /etc/nginx/nginx.conf

# 暴露端口
EXPOSE 80

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:80 || exit 1

# 启动 Nginx
CMD ["nginx", "-g", "daemon off;"]
