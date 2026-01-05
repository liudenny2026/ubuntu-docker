FROM docker:24.0.7-cli

# 替换为国内镜像源以提高下载速度和稳定性
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

# 更新包索引并安装必要的依赖（使用 openssh-client 而不是 openssh）
RUN apk update && apk add --no-cache ca-certificates curl git openssh-client

WORKDIR /app
COPY . /app

# 默认命令
CMD ["sh", "-c", "echo 'Build environment ready'"]