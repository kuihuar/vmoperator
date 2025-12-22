# kubeconfig Server 地址说明

## 问题说明

k3s 安装后，kubeconfig 中的 server 地址默认是 `https://127.0.0.1:6443`。

## 是否需要修改？

### 情况 1: 只在虚拟机内使用 kubectl（当前情况）

**不需要修改**，`127.0.0.1` 可以正常工作。

- ✅ 在虚拟机内执行 `kubectl` 命令：可以正常使用
- ✅ 在虚拟机内运行 Operator/Controller：可以正常使用
- ✅ 证书验证：正常（因为证书是为 127.0.0.1 签发的）

### 情况 2: 从外部（如 macOS 开发机）访问

**需要修改**为虚拟机实际 IP：`192.168.1.141`

- ❌ 从外部执行 `kubectl`：会失败（证书不匹配）
- ❌ 从外部访问 API Server：会失败

## 如何修改

### 方法 1: 修改现有 kubeconfig

```bash
# 修改 server 地址
sed -i 's|server: https://127.0.0.1:6443|server: https://192.168.1.141:6443|g' ~/.kube/config

# 验证
kubectl config view | grep server
```

### 方法 2: 使用修复脚本

```bash
sudo ./scripts/fix-kubeconfig-permissions.sh
```

脚本会询问是否需要修改 server 地址。

## 证书问题

如果遇到 `x509: certificate signed by unknown authority` 错误：

### 原因

- k3s 的证书是为 `127.0.0.1` 或 `localhost` 签发的
- 如果使用 `192.168.1.141` 访问，证书验证会失败

### 解决方案

#### 方案 1: 使用 127.0.0.1（推荐，如果只在虚拟机内使用）

保持 `127.0.0.1`，不需要修改。

#### 方案 2: 重新安装 k3s 时指定 IP

```bash
# 卸载 k3s
sudo /usr/local/bin/k3s-uninstall.sh

# 使用指定 IP 安装
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san 192.168.1.141" sh -
```

这样 k3s 的证书会包含 `192.168.1.141`，可以从外部访问。

#### 方案 3: 禁用证书验证（不推荐，仅用于测试）

在 kubeconfig 中添加：

```yaml
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://192.168.1.141:6443
```

## 当前情况建议

**如果你只在虚拟机内使用**（运行 Operator、执行 kubectl 命令）：

✅ **不需要修改**，保持 `127.0.0.1` 即可

**如果你需要从 macOS 开发机访问**：

1. 重新安装 k3s 时指定 IP（方案 2，推荐）
2. 或者修改 kubeconfig 并接受证书警告（方案 3，不推荐）

## 验证

```bash
# 检查当前 server 地址
kubectl config view | grep server

# 测试连接
kubectl get nodes
```

