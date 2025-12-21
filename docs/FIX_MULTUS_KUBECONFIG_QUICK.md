# 快速修复 Multus kubeconfig 缺失问题

## 问题

Pod 无法启动，错误信息：
```
Multus: error getting k8s client: GetK8sClient: failed to get context for the kubeconfig /etc/cni/net.d/multus.d/multus.kubeconfig: stat /etc/cni/net.d/multus.d/multus.kubeconfig: no such file or directory
```

## 立即修复（一行命令）

```bash
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d && \
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig && \
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig && \
sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig && \
echo "✓ 修复完成"
```

## 使用脚本修复

```bash
./scripts/fix-multus-kubeconfig-now.sh
```

## 验证修复

```bash
# 检查文件是否存在
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 应该看到类似输出：
# -rw-r--r-- 1 root root 1234 Dec 21 20:00 multus.kubeconfig
```

## 重启受影响的 Pod

修复后，删除受影响的 Pod 让其自动恢复：

```bash
# 删除特定的 Pod
kubectl delete pod -n rook-ceph rook-ceph-operator-84f6b7f9fb-ld7st

# 或删除所有 Rook Pod
kubectl delete pods -n rook-ceph --all

# 等待 Pod 恢复
kubectl get pods -n rook-ceph -w
```

## 为什么需要这个文件？

Multus CNI 需要 kubeconfig 文件来：
- 与 Kubernetes API Server 通信
- 读取 NetworkAttachmentDefinition CRD
- 管理 Pod 的网络配置

## 文件路径说明

- **主机路径**: `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig`
- **Pod 内路径**: `/etc/cni/net.d/multus.d/multus.kubeconfig`（通过挂载）

这两个路径指向同一个文件，因为 Multus DaemonSet 将主机路径挂载到 Pod 内的 `/etc/cni/net.d`。

