# Multus 权限问题诊断与修复

## 问题根源

`/var/lib/rancher/k3s/agent` 目录的权限为 `700` (drwx------)，只有 root 用户可以访问。

如果 Multus Pod 不是以 root 用户运行，它将无法访问该目录下的 kubeconfig 文件，导致：
- Multus Pod 无法初始化
- 所有 Pod（包括 Ceph）无法创建，报错：`failed to get context for the kubeconfig`

## 检查权限

运行检查脚本：

```bash
sudo ./scripts/check-multus-permissions.sh
```

### 关键检查点

1. **目录权限**
   ```bash
   sudo ls -ld /var/lib/rancher/k3s/agent
   # 输出：drwx------ 5 root root 4096 ... (权限 700)
   ```

2. **Multus Pod 运行用户**
   ```bash
   kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsUser}'
   # 如果为空，可能使用默认值（非 root）
   ```

3. **文件权限**
   ```bash
   sudo ls -l /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
   # 如果权限为 600，只有 root 可以读取
   ```

## 解决方案

### 方案 1：确保 Multus Pod 以 root 运行（推荐）

这是最简单且安全的方法。k3s 的 `/var/lib/rancher/k3s/agent` 目录权限是 700 是出于安全考虑，我们应该让 Multus Pod 以 root 运行来匹配这个限制。

#### 1.1 检查当前配置

```bash
kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 10 "securityContext"
```

#### 1.2 如果未配置，添加 root 用户配置

```bash
kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/securityContext",
    "value": {
      "runAsUser": 0,
      "runAsGroup": 0
    }
  }
]'
```

#### 1.3 重启 Pod

```bash
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0
```

### 方案 2：修改 kubeconfig 文件权限

如果 Multus Pod 不能以 root 运行，可以放宽文件权限（但不推荐，因为 kubeconfig 包含敏感信息）。

```bash
# 将文件权限改为 644（所有用户可读）
sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

**注意**：这仍然无法解决目录权限 700 的问题，除非 Multus Pod 以 root 运行。

### 方案 3：使用不同的目录（不推荐）

将 kubeconfig 文件放在权限更宽松的目录，但需要修改 DaemonSet 挂载配置，可能影响其他配置。

## 推荐配置

### Multus DaemonSet 安全上下文配置

```yaml
spec:
  template:
    spec:
      containers:
      - name: kube-multus
        securityContext:
          runAsUser: 0      # root
          runAsGroup: 0     # root
          capabilities:
            add:
            - NET_ADMIN
            - SYS_ADMIN
        volumeMounts:
        - name: cni
          mountPath: /host/etc/cni/net.d
```

### kubeconfig 文件权限

```bash
# 644：root 可读写，其他用户可读
sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

## 验证修复

1. **检查 Pod 运行用户**
   ```bash
   MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n kube-system $MULTUS_POD -- id
   # 应该显示：uid=0(root) gid=0(root)
   ```

2. **检查文件访问**
   ```bash
   kubectl exec -n kube-system $MULTUS_POD -- ls -l /host/etc/cni/net.d/multus.d/multus.kubeconfig
   kubectl exec -n kube-system $MULTUS_POD -- cat /host/etc/cni/net.d/multus.d/multus.kubeconfig > /dev/null
   echo $?  # 应该返回 0
   ```

3. **检查 Multus Pod 状态**
   ```bash
   kubectl get pods -n kube-system -l app=multus
   # 应该显示 Running
   ```

4. **测试创建 Pod**
   ```bash
   kubectl run test-pod --image=nginx --rm -it --restart=Never
   ```

## 为什么 k3s agent 目录权限是 700？

这是 k3s 的安全设计：
- `/var/lib/rancher/k3s/agent` 包含 k3s 的运行时数据和配置
- 权限 700 确保只有 root 可以访问，防止其他用户查看敏感信息
- 这也是为什么 k3s 组件通常需要以 root 运行

## 总结

**问题**：`/var/lib/rancher/k3s/agent` 权限 700，Multus Pod 如果不是 root 无法访问

**解决方案**：确保 Multus Pod 以 root 运行（方案 1）

**验证**：Pod 内可以访问 kubeconfig 文件，Multus 正常工作

