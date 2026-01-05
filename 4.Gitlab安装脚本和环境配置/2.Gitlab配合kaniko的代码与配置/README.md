# Kaniko 学习示例

这是一个简化的 Kaniko 构建示例，用于学习 Docker 镜像构建过程。

## 项目结构

```
kaniko-demo/
├── .gitlab-ci.yml      # GitLab CI/CD 配置
├── Dockerfile          # Docker 镜像构建配置
├── packages/           # （可选）本地依赖包
│   └── README.md
└── README.md
```

## 镜像内容

这个镜像包含：
- **基础镜像**: Ubuntu 24.04（从私有 Harbor 拉取）
- **Web 服务器**: Nginx
- **工具**: curl, vim, net-tools, iputils-ping
- **静态页面**: 简单的 HTML 页面

## Kaniko 构建流程

### 1. GitLab CI 触发
```yaml
# 提交代码到 main/master 分支时自动触发
```

### 2. Kaniko 执行步骤
```
1. 配置 Docker 认证（Harbor）
2. 从 192.168.40.248 拉取基础镜像 ubuntu:24.04
3. 执行 Dockerfile 中的指令
   - 替换 Ubuntu 源为阿里云
   - 安装 nginx 和工具
   - 创建静态页面
4. 构建完成，推送镜像到 Harbor
```

### 3. 构建结果
- 镜像名: `192.168.40.248/library/kaniko-demo:<commit-sha>`
- 镜像名: `192.168.40.248/library/kaniko-demo:latest`
- 镜像大小: 约 100-200MB（相比 GitLab 的几GB小很多）

## 使用方法

### 构建镜像
```bash
# 提交代码，自动触发 CI 构建
git add .
git commit -m "Update demo"
git push origin main
```

### 运行镜像
```bash
# 从 Harbor 拉取镜像
docker pull 192.168.40.248/library/kaniko-demo:latest

# 运行容器
docker run -d -p 8080:80 192.168.40.248/library/kaniko-demo:latest

# 访问
curl http://localhost:8080
```

### 本地测试（可选）
如果想在本地构建测试：
```bash
# 本地 Docker 构建
docker build -t kaniko-demo .

# 本地运行
docker run -d -p 8080:80 kaniko-demo
```

## Kaniko 学习要点

### 1. 无守护进程
Kaniko 不需要 Docker 守护进程，直接在用户空间执行构建。

### 2. 安全性
适合在 Kubernetes 等容器环境中使用，不需要特权模式。

### 3. 缓存支持
- `--cache=true`: 启用构建缓存
- `--cache-ttl=24h`: 缓存有效期 24 小时
- `--cache-repo`: 指定缓存仓库

### 4. 多阶段构建
本示例使用单阶段构建，如需多阶段：
```dockerfile
# 构建阶段
FROM ubuntu:24.04 AS builder
# 编译代码...

# 运行阶段
FROM ubuntu:24.04
COPY --from=builder /app /app
```

### 5. 私有仓库认证
```yaml
# 配置 Harbor 认证
echo "{\"auths\":{\"192.168.40.248\":{\"username\":\"$HARBOR_USERNAME\",\"password\":\"$HARBOR_PASSWORD\"}}}" > /kaniko/.docker/config.json
```

## 对比：GitLab vs Demo

| 项目 | 镜像大小 | 构建时间 | 学习难度 |
|------|---------|---------|---------|
| GitLab CE | 2-3 GB | 30-60 分钟 | 困难（步骤多、依赖多） |
| Nginx Demo | 100-200 MB | 2-5 分钟 | 简单（快速验证） |

## 下一步学习

1. 修改 Dockerfile，添加更多功能
2. 尝试多阶段构建
3. 测试 Kaniko 缓存机制
4. 使用 BuildKit 特性
5. 探索 Kaniko 高级选项

## 参考资料

- [Kaniko 官方文档](https://github.com/GoogleContainerTools/kaniko)
- [Kaniko 最佳实践](https://github.com/GoogleContainerTools/kaniko#kaniko-build-contexts)
