# 从 macOS 访问 k3s 集群

## 前提条件

- 虚拟机 IP: `192.168.1.141`
- k3s 运行在虚拟机上
- macOS 和虚拟机在同一网络

## 方法 1: 重新安装 k3s（推荐，证书正确）

这是最可靠的方法，让 k3s 的证书包含虚拟机 IP。

### 步骤

```bash
# 在虚拟机上执行

# 1. 卸载当前 k3s
sudo /usr/local/bin/k3s-uninstall.sh

# 2. 使用指定 IP 重新安装
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san 192.168.1.141" sh -

# 3. 配置 kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# 4. 修改 server 地址为虚拟机 IP
sed -i 's|server: https://127.0.0.1:6443|server: https://192.168.1.141:6443|g' ~/.kube/config
```

### 在 macOS 上

```bash
# 1. 从虚拟机复制 kubeconfig 到 macOS
scp jianfen@192.168.1.141:~/.kube/config ~/.kube/config-k3s

# 2. 修改 server 地址（如果还没改）
sed -i '' 's|server: https://127.0.0.1:6443|server: https://192.168.1.141:6443|g' ~/.kube/config-k3s

# 3. 使用这个 kubeconfig
export KUBECONFIG=~/.kube/config-k3s

# 4. 测试连接
kubectl get nodes
```

---

## 方法 2: 修改现有 k3s 配置（不重新安装）

如果不想重新安装，可以修改 k3s 配置并重启。

### 在虚拟机上

```bash
# 1. 修改 k3s 配置
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml > /dev/null <<EOF
tls-san:
  - 192.168.1.141
EOF

# 2. 重启 k3s
sudo systemctl restart k3s

# 3. 等待重启完成
sleep 30

# 4. 重新配置 kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
sed -i 's|server: https://127.0.0.1:6443|server: https://192.168.1.141:6443|g' ~/.kube/config
```

### 在 macOS 上

```bash
# 1. 从虚拟机复制 kubeconfig
scp jianfen@192.168.1.141:~/.kube/config ~/.kube/config-k3s

# 2. 使用
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

---

## 方法 3: 使用 SSH 隧道（临时方案）

如果不想修改 k3s 配置，可以使用 SSH 隧道。

### 在 macOS 上

```bash
# 1. 创建 SSH 隧道（在后台运行）
ssh -f -N -L 6443:127.0.0.1:6443 jianfen@192.168.1.141

# 2. 从虚拟机复制 kubeconfig（保持 127.0.0.1）
scp jianfen@192.168.1.141:~/.kube/config ~/.kube/config-k3s

# 3. 使用
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

**注意**：SSH 隧道需要保持连接，关闭终端后隧道会断开。

---

## 推荐方案对比

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| 方法 1（重新安装） | 证书正确，最可靠 | 需要重新安装 | ⭐⭐⭐⭐⭐ |
| 方法 2（修改配置） | 不需要重新安装 | 需要重启 k3s | ⭐⭐⭐⭐ |
| 方法 3（SSH 隧道） | 不需要修改 k3s | 需要保持 SSH 连接 | ⭐⭐⭐ |

---

## 验证连接

在 macOS 上执行：

```bash
# 设置 kubeconfig
export KUBECONFIG=~/.kube/config-k3s

# 测试连接
kubectl get nodes
kubectl get pods -A
```

---

## 配置 kubectl 上下文（可选）

如果 macOS 上有多个集群，可以配置上下文：

```bash
# 查看当前上下文
kubectl config get-contexts

# 重命名上下文
kubectl config rename-context default k3s-cluster

# 切换上下文
kubectl config use-context k3s-cluster
```

---

## 故障排查

### 问题 1: 连接超时

```bash
# 检查网络连通性
ping 192.168.1.141

# 检查端口是否开放
nc -zv 192.168.1.141 6443
```

### 问题 2: 证书验证失败

如果使用 `192.168.1.141` 但证书是为 `127.0.0.1` 签发的，会报错。

**解决**：使用方法 1 或方法 2，让证书包含 `192.168.1.141`。

### 问题 3: 权限被拒绝

```bash
# 检查 kubeconfig 权限
ls -la ~/.kube/config-k3s

# 应该是 600
chmod 600 ~/.kube/config-k3s
```

---

**最后更新**: 2025-12-22

