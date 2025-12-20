# 修复 Multus 在 k3s 环境中的配置问题

## 问题描述

Multus 在 k3s 环境中报错：
```
failed to find the primary CNI plugin: failed to find the cluster master CNI plugin: could not find a plugin configuration in /host/etc/cni/net.d
```

## 原因分析

k3s 使用的 CNI 配置路径与标准 Kubernetes 不同：
- **标准 Kubernetes**: `/etc/cni/net.d/`
- **k3s**: `/var/lib/rancher/k3s/agent/etc/cni/net.d/`

Multus DaemonSet 默认挂载的是标准路径，无法找到 k3s 的 CNI 配置。

## 解决方案

### 方案 1: 更新 Multus DaemonSet（推荐）

更新 Multus DaemonSet 的 volumeMounts 和 volumes，使用正确的 k3s 路径：

```bash
kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {
        "name": "cni",
        "mountPath": "/host/etc/cni/net.d"
      },
      {
        "name": "cnibin",
        "mountPath": "/host/opt/cni/bin"
      }
    ]
  },
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
      },
      {
        "name": "cnibin",
        "hostPath": {
          "path": "/var/lib/rancher/k3s/data/current/bin",
          "type": "Directory"
        }
      }
    ]
  }
]'
```

然后删除 Pod 以触发重启：
```bash
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0
```

### 方案 2: 手动编辑 DaemonSet

```bash
kubectl edit daemonset -n kube-system kube-multus-ds
```

修改以下部分：

**volumeMounts:**
```yaml
volumeMounts:
  - name: cni
    mountPath: /host/etc/cni/net.d
  - name: cnibin
    mountPath: /host/opt/cni/bin
```

**volumes:**
```yaml
volumes:
  - name: cni
    hostPath:
      path: /var/lib/rancher/k3s/agent/etc/cni/net.d
      type: Directory
  - name: cnibin
    hostPath:
      path: /var/lib/rancher/k3s/data/current/bin
      type: Directory
```

### 方案 3: 使用脚本自动修复

运行修复脚本：
```bash
./scripts/fix-multus-k3s.sh
```

## 验证修复

修复后，检查 Multus Pod 日志：

```bash
# 检查 Pod 状态
kubectl get pods -n kube-system -l app=multus

# 检查日志（应该没有错误）
kubectl logs -n kube-system -l app=multus --tail=50
```

应该看到类似以下内容（没有错误）：
```
[verbose] multus-daemon started
[info] Found primary CNI plugin: flannel
```

## 检查 k3s CNI 配置

验证 k3s 的 CNI 配置存在：

```bash
# 检查配置文件
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

# 查看配置内容
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf
```

通常 k3s 使用 Flannel，配置文件可能是 `10-flannel.conflist`。

## 如果仍然失败

如果修复后仍然失败，检查：

1. **CNI 配置路径是否正确**：
   ```bash
   sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
   ```

2. **Multus Pod 是否能够访问挂载的目录**：
   ```bash
   kubectl exec -n kube-system -it <multus-pod> -- ls -la /host/etc/cni/net.d/
   ```

3. **检查 Multus 日志**：
   ```bash
   kubectl logs -n kube-system -l app=multus --tail=100
   ```

4. **检查 DaemonSet 配置**：
   ```bash
   kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 20 "volumes:"
   ```

## 注意事项

- k3s 的 CNI 二进制文件路径可能因版本而异，如果 `/var/lib/rancher/k3s/data/current/bin` 不存在，尝试：
  - `/var/lib/rancher/k3s/agent/bin`
  - `/usr/local/bin`

- 某些 k3s 版本可能使用不同的 CNI 配置路径，根据实际情况调整。

