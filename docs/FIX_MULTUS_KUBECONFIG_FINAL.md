# 彻底解决 Multus kubeconfig 问题

## 问题根源

Multus 在 Pod 内查找 `/etc/cni/net.d/multus.d/multus.kubeconfig`，但文件不存在或路径不匹配。

## 完整解决方案

### 步骤 1: 运行诊断脚本

```bash
./scripts/diagnose-and-fix-multus-kubeconfig.sh
```

### 步骤 2: 如果脚本无法修复，手动检查

#### 2.1 检查文件是否存在

```bash
# 检查主机文件
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 如果不存在，创建它
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

#### 2.2 检查 Multus DaemonSet 挂载

```bash
# 检查挂载配置
kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 10 "volumes:"
kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 10 "volumeMounts:"
```

**期望的配置**:
- `volumes[].hostPath.path`: `/var/lib/rancher/k3s/agent/etc/cni/net.d`
- `volumeMounts[].mountPath`: `/etc/cni/net.d`

#### 2.3 如果挂载不正确，修复 DaemonSet

```bash
# 方法 1: 使用 patch
kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "cni",
        "hostPath": {
          "path": "/var/lib/rancher/k3s/agent/etc/cni/net.d",
          "type": "Directory"
        }
      }
    ]
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {
        "name": "cni",
        "mountPath": "/etc/cni/net.d"
      }
    ]
  }
]'

# 重启 Pod
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0
```

#### 2.4 检查 Multus 配置文件中的路径

```bash
# 查看配置文件
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | grep kubeconfig
```

如果配置中的路径是 `/host/etc/cni/net.d/multus.d/multus.kubeconfig`，但 Pod 内挂载到 `/etc/cni/net.d`，需要修改配置文件。

#### 2.5 验证 Pod 内访问

```bash
# 获取 Multus Pod
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}')

# 检查文件
kubectl exec -n kube-system $MULTUS_POD -- ls -la /etc/cni/net.d/multus.d/multus.kubeconfig

# 如果失败，尝试
kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/multus.d/multus.kubeconfig
```

### 步骤 3: 重启所有受影响的 Pod

修复后，重启 Pod：

```bash
# 重启 Multus Pod
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0

# 重启 Rook Pods
kubectl delete pods -n rook-ceph --all --force --grace-period=0

# 等待恢复
kubectl get pods -n rook-ceph -w
```

## 快速修复（如果上面都不行）

如果以上方法都不行，可以临时禁用 Multus 对某些 Pod 的影响，或者重新安装 Multus：

```bash
# 重新安装 Multus（会重新配置所有路径）
./scripts/install-multus-kubectl-k3s.sh
```

## 总结

问题的关键是：
1. ✅ **文件必须存在**：`/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig`
2. ✅ **DaemonSet 必须正确挂载**：主机路径 → Pod 内的 `/etc/cni/net.d`
3. ✅ **配置文件路径必须匹配**：Multus 配置中的 kubeconfig 路径必须与 Pod 内的实际路径匹配

