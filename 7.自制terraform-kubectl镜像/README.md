# terraform-kubectl Docker Image

包含 Terraform 和 kubectl 的 Docker 镜像，用于 GitLab CI/CD 流水线验证。

## 版本信息

- Terraform: 1.14.3
- kubectl: v1.35.0
- Kubernetes Provider: 2.32.0 (预装)

## 构建镜像

```bash
docker build -t 192.168.40.248/library/terraform-kubectl:2026-1-12 .
docker push 192.168.40.248/library/terraform-kubectl:2026-1-12
```

## GitLab CI/CD 变量配置

在 GitLab 项目设置中配置以下变量：

| 变量名 | 说明 | 建议 |
|--------|------|------|
| `KUBE_SERVER` | Kubernetes API 地址 | `https://192.168.40.241:6443` |
| `KUBE_CA_PEM` | CA 证书 (Base64) | Protected: 是 |
| `KUBE_CLIENT_CERT_DATA` | 客户端证书 (Base64) | Protected: 是 |
| `KUBE_CLIENT_KEY_DATA` | 客户端私钥 (Base64) | Protected: 是 |

### 提取证书

从现有 kubeconfig 提取证书：

```bash
# CA 证书
grep "certificate-authority-data" ~/.kube/config | awk '{print $2}'

# 客户端证书
grep "client-certificate-data" ~/.kube/config | awk '{print $2}'

# 客户端私钥
grep "client-key-data" ~/.kube/config | awk '{print $2}'
```

## 镜像特性

- 非root用户运行
- 预装 Kubernetes provider，无需下载
- 插件缓存目录
- KUBECONFIG 环境变量预设
