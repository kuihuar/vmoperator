# Docker Registry 连接测试说明

## 为什么测试可能显示失败？

### 原因 1: HTTP 401 是正常的

Docker Registry 的 `/v2/` 端点默认返回 `401 Unauthorized`，这是**正常行为**，表示：
- ✅ 连接正常
- ✅ Registry 可访问
- ⚠️  需要认证（但公开镜像不需要）

**测试方法**：
```bash
# 测试 registry 连接
curl -I https://registry-1.docker.io/v2/

# 返回 401 是正常的：
# HTTP/1.1 401 Unauthorized
# Www-Authenticate: Bearer realm="https://auth.docker.io/token",service="registry.docker.io"
```

### 原因 2: 测试端点不正确

应该测试：
- ✅ `https://registry-1.docker.io/v2/` - Registry API（可能返回 401，正常）
- ✅ `https://auth.docker.io/` - 认证服务
- ❌ `https://hub.docker.com/` - 这是网站，不是 registry

### 原因 3: 网络延迟或超时

如果连接超时，可能是：
- 网络延迟高
- 防火墙阻止
- DNS 解析慢

## 正确的测试方法

### 方法 1: 测试 Registry API（推荐）

```bash
# 测试 registry，401 表示可访问
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://registry-1.docker.io/v2/)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    echo "✓ Registry 可访问 (HTTP $HTTP_CODE)"
fi
```

### 方法 2: 测试认证服务

```bash
# 测试认证服务
curl -I https://auth.docker.io/ | head -1
# 应该返回: HTTP/1.1 200 OK
```

### 方法 3: 直接测试拉取镜像

```bash
# 最可靠的方法：直接尝试拉取镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl pull rancher/mirrored-pause:3.6

# 如果成功或显示 "already exists"，说明可以访问
```

## 实际验证

最可靠的验证方法是**直接拉取镜像**：

```bash
# 配置 crictl
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml

# 尝试拉取镜像
crictl pull rancher/mirrored-pause:3.6

# 如果成功，说明 Docker Hub 完全可访问
# 如果失败，查看错误信息
```

## 总结

- **HTTP 401 是正常的**：表示 Registry 可访问，只是需要认证
- **最可靠的测试**：直接尝试拉取镜像
- **如果拉取失败**：检查网络、DNS、防火墙

脚本中的测试可能显示失败，但实际上 Registry 可能是可访问的（返回 401）。最可靠的方法是直接尝试拉取镜像。

