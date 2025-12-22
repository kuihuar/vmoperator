# Multus CNI 官方推荐配置（结合 k3s）

根据 [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md)，以下是关键配置要点和项目中的问题。

## 官方文档关键要点

### 1. kubeconfig 路径

官方文档显示的配置：

```json
{
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig"
}
```

**关键点**：
- 配置文件中的路径是 `/etc/cni/net.d/multus.d/multus.kubeconfig`
- 这是**主机上的绝对路径**（不是 Pod 内路径）
- 对于 k3s，实际路径是 `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig`

### 2. kubeconfig 创建方式

官方推荐使用 ServiceAccount 的 token 和 CA 创建 kubeconfig，而不是直接复制 k3s.yaml：

```bash
mkdir -p /etc/cni/net.d/multus.d
SERVICEACCOUNT_CA=$(kubectl get secrets -n=kube-system -o json | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .data."ca.crt"')
SERVICEACCOUNT_TOKEN=$(kubectl get secrets -n=kube-system -o json | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .data.token' | base64 -d )
KUBERNETES_SERVICE_PROTOCOL=$(kubectl get all -o json | jq -r .items[0].spec.ports[0].name)
KUBERNETES_SERVICE_HOST=$(kubectl get all -o json | jq -r .items[0].spec.clusterIP)
KUBERNETES_SERVICE_PORT=$(kubectl get all -o json | jq -r .items[0].spec.ports[0].port)
cat > /etc/cni/net.d/multus.d/multus.kubeconfig <<EOF
# Kubeconfig file for Multus CNI plugin.
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: ${KUBERNETES_SERVICE_PROTOCOL:-https}://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}
    certificate-authority-data: ${SERVICEACCOUNT_CA}
users:
- name: multus
  user:
    token: "${SERVICEACCOUNT_TOKEN}"
contexts:
- name: multus-context
  context:
    cluster: local
    user: multus
current-context: multus-context
EOF
chmod 600 /etc/cni/net.d/multus.d/multus.kubeconfig
```

### 3. Thick Plugin vs Thin Plugin

- **Thin Plugin**: CNI 插件直接在主机上运行，配置文件中的路径必须是主机路径
- **Thick Plugin**: 通过 DaemonSet 运行，daemon-config.json 中的路径可以使用 Pod 内路径（通过挂载访问）

## 项目中发现的问题

### 问题 1: 配置文件路径不一致

**当前情况**：
- `00-multus.conf` 中配置：`"/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"`（主机路径）✅ 正确
- `daemon-config.json` 中配置：`"/host/etc/cni/net.d/multus.d/multus.kubeconfig"`（Pod 内路径）✅ 也正确

但错误信息显示找不到文件，说明：
1. 文件确实存在
2. 但 Multus 可能无法正确访问（权限或路径解析问题）

### 问题 2: kubeconfig 创建方式不推荐

**当前方式**：直接复制 k3s.yaml 并修改 server 地址

**问题**：
- 使用 k3s.yaml 的完整凭证，权限过大
- 不是官方推荐的方式

**建议**：使用 ServiceAccount token 创建专用 kubeconfig（更安全）

### 问题 3: 路径配置混乱

**混淆点**：
- CNI 配置文件（`00-multus.conf`）中的路径：主机路径
- Thick Plugin 配置（`daemon-config.json`）中的路径：Pod 内路径（通过 `/host` 挂载点访问）

这两个配置用于不同的场景，不应该混淆。

## 推荐修复方案

### 方案 1: 使用官方推荐方式创建 kubeconfig（推荐）

```bash
# 1. 创建目录
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d

# 2. 使用官方推荐方式创建 kubeconfig
SERVICEACCOUNT_CA=$(kubectl get secrets -n=kube-system -o json | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .data."ca.crt"')
SERVICEACCOUNT_TOKEN=$(kubectl get secrets -n=kube-system -o json | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .data.token' | base64 -d)
KUBERNETES_SERVICE_HOST=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')
KUBERNETES_SERVICE_PORT=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.ports[0].port}')

sudo tee /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig > /dev/null <<EOF
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}
    certificate-authority-data: ${SERVICEACCOUNT_CA}
users:
- name: multus
  user:
    token: "${SERVICEACCOUNT_TOKEN}"
contexts:
- name: multus-context
  context:
    cluster: local
    user: multus
current-context: multus-context
EOF

sudo chmod 600 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

### 方案 2: 确保配置文件路径正确

**对于 00-multus.conf（CNI 插件使用）**：
```json
{
  "kubeconfig": "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
}
```
✅ 主机路径，正确

**对于 daemon-config.json（Thick Plugin 使用）**：
```json
{
  "kubeconfig": "/host/etc/cni/net.d/multus.d/multus.kubeconfig"
}
```
✅ Pod 内路径（通过挂载访问主机路径），正确

### 方案 3: 如果使用 DaemonSet 安装，使用官方自动配置

官方文档提到 DaemonSet 会自动配置，可以：

1. **使用官方 DaemonSet**：
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
   ```

2. **或者使用 Helm Chart**（官方推荐）：
   ```bash
   helm repo add multus https://k8snetworkplumbingwg.github.io/multus-cni/
   helm install multus multus/multus
   ```

这样可以避免手动配置路径的问题。

## 当前问题的可能原因

根据错误信息 `context deadline exceeded`，可能的原因：

1. **kubeconfig 配置问题**：
   - server 地址不正确
   - token 无效或过期
   - CA 证书问题

2. **网络连接问题**：
   - Multus 无法连接到 Kubernetes API Server
   - 防火墙或网络策略阻止

3. **权限问题**：
   - ServiceAccount 权限不足
   - kubeconfig 文件权限问题

## 建议的解决步骤

1. **使用官方方式重新创建 kubeconfig**
2. **验证 kubeconfig 可以正常工作**：
   ```bash
   KUBECONFIG=/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig kubectl get pods
   ```
3. **如果使用 DaemonSet，确保 Pod 以正确权限运行**
4. **检查 Multus DaemonSet 日志**，查看具体错误

## 总结

关键要点：
1. ✅ CNI 配置文件中的路径必须是主机绝对路径
2. ✅ 使用 ServiceAccount token 创建 kubeconfig 更安全
3. ✅ 对于 k3s，路径是 `/var/lib/rancher/k3s/agent/etc/cni/net.d/...`
4. ✅ Thick Plugin 的 daemon-config.json 可以使用 Pod 内路径（通过挂载）
5. ⚠️ 当前错误可能是 kubeconfig 连接问题，而不是路径问题

