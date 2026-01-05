# GitLab CI/CD Buildx 配置

使用 Docker-in-Docker 和 BuildKit 进行构建。

## 配置说明

使用 Docker-in-Docker (DinD) 模式，通过挂载 Docker socket 实现容器内构建。

### 配置重点特别说明

- **Runner 名称**: buildx
- **GitLab URL**: http://192.168.40.249
- **Runner Token**: glrt-... (已配置)
- **执行器**: docker
- **基础镜像**: docker:24.0.7-cli (包含 Docker 客户端)
- **特权模式**: false (非特权模式，更安全)
- **私有仓库**: http://192.168.40.248 (配置为不安全注册表)
- **Docker Socket**: 挂载到容器内

## 构建流程

代码提交后自动构建。

## 故障排查

### 网络超时或无法拉取镜像

如果遇到网络超时错误，可以在服务中配置镜像加速器：
```
services:
  - name: docker:24.0.7-dind
    command: ["--insecure-registry", "192.168.40.248", "--registry-mirror", "https://docker.mirrors.ustc.edu.cn", "--registry-mirror", "https://docker.1ms.run"]
```

### Git 命令未找到及 APK 包安装失败

如果遇到 `git was not found in the system` 或 `apk add` 命令失败错误，当前 Dockerfile 已包含解决方案：
```
# 替换为国内镜像源以提高下载速度和稳定性
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

# 更新包索引并安装必要的依赖（使用 openssh-client 而不是 openssh）
RUN apk update && apk add --no-cache ca-certificates curl git openssh-client
```
此配置会使用国内镜像源（USTC）来提高包下载成功率，并安装包括 git 在内的必要工具。

### Docker-in-Docker 权限问题

当前配置使用 `privileged = false`（非特权模式），更加安全。如果需要更深入的系统访问权限，可能需要在 Runner 配置中启用 `privileged = true`，但这会降低安全性。

## 参考资料

- [GitLab CI/CD 文档](https://docs.gitlab.com/ee/ci/)
- [Docker Buildx 文档](https://docs.docker.com/buildx/working-with-buildx/)
