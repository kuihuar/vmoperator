# 修复 Multus kubeconfig 文件缺失

## 问题描述

Multus Pod 或其他使用 Multus 网络的 Pod 无法启动，错误信息：

```
Multus: error getting k8s client: GetK8sClient: failed to get context for the kubeconfig /etc/cni/net.d/multus.d/multus.kubeconfig: stat /etc/cni/net.d/multus.d/multus.kubeconfig: no such file or directory
```

## 原因

Multus 需要 kubeconfig 文件来与 Kubernetes API Server 通信，但该文件未被创建或丢失。

## 解决方案

### 方法 1: 使用修复脚本（推荐）

```bash
./scripts/fix-multus-kubeconfig.sh
```

脚本会自动：
1. 检查 Multus Pod 状态
2. 从 k3s kubeconfig 或 ServiceAccount Secret 创建 multus.kubeconfig
3. 验证文件是否正确

### 方法 2: 手动创建

#### 步骤 1: 创建目录

```bash
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d
```

#### 步骤 2: 创建 kubeconfig 文件

**选项 A: 使用 k3s kubeconfig（最简单）**

```bash
# 复制 k3s kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 修改 server 地址为集群内部地址
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 设置权限
sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

**选项 B: 使用 ServiceAccount Token**

```bash
# 获取 ServiceAccount Secret
SA_NAME="kube-multus-ds"  # 或你的 Multus ServiceAccount 名称
SECRET_NAME=$(kubectl get serviceaccount -n kube-system $SA_NAME -o jsonpath='{.secrets[0].name}')

# 获取 Token 和 CA
TOKEN=$(kubectl get secret -n kube-system $SECRET_NAME -o jsonpath='{.data.token}' | base64 -d)
CA_CERT=$(kubectl get secret -n kube-system $SECRET_NAME -o jsonpath='{.data.ca\.crt}')

# 创建 kubeconfig
sudo tee /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig > /dev/null <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT}
    server: https://kubernetes.default.svc:443
  name: cluster
contexts:
- context:
    cluster: cluster
    user: multus
  name: multus-context
current-context: multus-context
users:
- name: multus
  user:
    token: ${TOKEN}
EOF

sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

#### 步骤 3: 验证文件

```bash
# 检查文件是否存在
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 检查内容
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

#### 步骤 4: 重启受影响的 Pod

```bash
# 删除受影响的 Pod，让它自动重新创建
kubectl delete pod -n rook-ceph ceph-csi-controller-manager-5dc6b7cf95-znbq6

# 或重启所有使用 Multus 的 Pod
kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[].securityContext.privileged==true or .metadata.annotations["k8s.v1.cni.cncf.io/networks"]) | "\(.metadata.namespace) \(.metadata.name)"' | xargs -n2 kubectl delete pod -n
```

## 验证修复

```bash
# 检查 Multus Pod 状态
kubectl get pods -n kube-system -l app=multus

# 检查受影响的 Pod 是否恢复
kubectl get pods -n rook-ceph

# 查看 Pod 日志（应该没有 kubeconfig 错误）
kubectl logs -n rook-ceph ceph-csi-controller-manager-5dc6b7cf95-znbq6
```

## 预防措施

确保 Multus 安装完成后：
1. Multus Pod 正常运行
2. kubeconfig 文件存在
3. 文件权限正确（644）

如果 Multus Pod 正常运行，它通常会自动创建 kubeconfig 文件。如果文件丢失，可能是：
- Multus Pod 未正常运行
- 文件被意外删除
- 权限问题

## 相关文档

- [Multus 安装指南](MULTUS_KUBECTL_K3S.md)
- [Multus 配置文档](https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html)

