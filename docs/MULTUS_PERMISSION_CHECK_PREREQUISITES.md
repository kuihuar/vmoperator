# Multus 权限检查的前提条件

## 权限检查的前提

在执行 Multus 权限检查之前，必须确保以下前提条件都满足：

### 1. ServiceAccount 存在

**检查**：
```bash
kubectl get sa -n kube-system multus
```

**必须存在**，否则权限检查没有意义。

### 2. ClusterRole 存在并正确配置

**检查**：
```bash
kubectl get clusterrole multus -o yaml
```

**必须包含**：
- `k8s.cni.cncf.io` API group 的所有权限
- `pods` 和 `pods/status` 的 `get` 和 `update` 权限

### 3. ClusterRoleBinding 存在并正确绑定

**检查**：
```bash
kubectl get clusterrolebinding multus -o yaml
```

**必须确保**：
- `roleRef.name` 是 `multus`
- `subjects[0].name` 是 `multus`
- `subjects[0].namespace` 是 `kube-system`

### 4. ServiceAccount Secret 存在（包含 token）

**检查**：
```bash
kubectl get secrets -n kube-system -o json | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .metadata.name'
```

**必须存在**，否则 kubeconfig 无法获取 token。

### 5. kubeconfig 文件存在且正确配置

**检查**：
```bash
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig | jq '.'
```

**必须包含**：
- 正确的 server 地址
- 有效的 token
- 正确的 CA 证书

### 6. Multus 配置文件中的路径正确

**检查**：
```bash
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | jq '.kubeconfig'
```

**必须指向**：
- 主机绝对路径（不是 Pod 内路径）
- k3s 中应该是：`/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig`

## 权限检查的顺序

正确的检查顺序应该是：

```
1. 检查前提条件
   ├─ ServiceAccount 是否存在？
   ├─ ClusterRole 是否存在？
   ├─ ClusterRoleBinding 是否存在？
   └─ Secret/token 是否存在？

2. 如果前提条件满足，再检查：
   ├─ ClusterRole 的权限配置是否正确？
   ├─ ClusterRoleBinding 的绑定是否正确？
   └─ kubeconfig 是否可以工作？

3. 如果所有前提条件满足，再测试实际权限
```

## 当前检查脚本的问题

当前的 `check-multus-permissions-detailed.sh` 脚本：
- ✅ 检查了 ServiceAccount、ClusterRole、ClusterRoleBinding
- ✅ 检查了 Secret
- ⚠️ 但没有明确验证这些前提条件是否都满足
- ⚠️ 如果前提条件不满足，检查结果可能不准确

## 建议的改进

应该在脚本开头添加前提条件检查，如果任何前提条件不满足，应该：
1. 明确提示缺失的前提条件
2. 建议如何修复
3. 可以继续检查，但标记结果可能不准确

## 实际使用场景

**什么时候需要检查权限？**

1. **安装 Multus 后**：验证 RBAC 配置是否正确
2. **Multus 无法工作时**：排查是否是权限问题
3. **更新 RBAC 配置后**：验证新配置是否生效

**什么时候不需要检查？**

1. **Multus 正常工作**：不需要检查权限
2. **其他组件问题**：如果问题明显不是权限相关的

## 总结

权限检查的前提是：
1. ✅ 所有 RBAC 资源（ServiceAccount、ClusterRole、ClusterRoleBinding）都存在
2. ✅ ServiceAccount 的 Secret/token 存在
3. ✅ kubeconfig 文件存在且配置正确
4. ✅ Multus 配置文件中的路径正确

只有当这些前提条件都满足时，权限检查的结果才是可靠的。

