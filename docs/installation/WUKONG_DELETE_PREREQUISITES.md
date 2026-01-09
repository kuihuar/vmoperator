# 删除 Wukong 资源的前置条件

## 概述

正常情况下删除 Wukong 资源需要满足以下前置条件，以确保资源能够被正确清理，不会留下孤立资源。

## 前置条件清单

### 1. ✅ 控制器必须运行

**原因**：Wukong 资源使用 Finalizer 机制，需要控制器执行清理逻辑并移除 finalizer。

**检查方法**：
```bash
# 检查 VM Operator 控制器是否运行
kubectl get pods -A | grep -E "controller|manager" | grep -v "kubevirt\|longhorn\|nmstate"

# 应该看到类似输出：
# default    novasphere-controller-manager-xxx   1/1   Running
```

**如果控制器未运行**：
- 删除操作会卡住，Wukong 资源会一直处于 `Terminating` 状态
- Finalizer `wukong.novasphere.dev/finalizer` 无法被移除
- 需要手动移除 finalizer 或重启控制器

---

### 2. ✅ VirtualMachine 必须可以被删除

**原因**：控制器会先删除 VirtualMachine，然后删除其他资源。

**检查方法**：
```bash
# 检查 VirtualMachine 状态
WUKONG_NAME="your-wukong-name"
VM_NAME="${WUKONG_NAME}-vm"
kubectl get vm $VM_NAME -n default

# 检查是否有 finalizer 阻止删除
kubectl get vm $VM_NAME -n default -o jsonpath='{.metadata.finalizers}'
```

**正常情况**：
- VirtualMachine 可以正常删除（即使正在运行，KubeVirt 会优雅停止）
- 没有其他 finalizer 阻止删除

**异常情况**：
- VirtualMachine 有 finalizer 但控制器无法处理
- VirtualMachine 被其他资源引用

---

### 3. ✅ DataVolume 和 PVC 必须可以被删除

**原因**：控制器会删除 DataVolume，然后删除 PVC。如果 PVC 被其他资源引用，删除会失败。

**检查方法**：
```bash
# 检查 PVC 是否被其他 Pod 使用
kubectl get pvc -n default | grep your-wukong-name

# 检查 PVC 的 finalizer
kubectl get pvc <pvc-name> -n default -o jsonpath='{.metadata.finalizers}'

# 检查是否有 Pod 正在使用 PVC
kubectl get pods -A -o json | jq '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="<pvc-name>")'
```

**正常情况**：
- PVC 没有被其他 Pod 或资源使用
- DataVolume 可以正常删除（如果有）
- PVC 的 `kubernetes.io/pvc-protection` finalizer 会在没有引用时自动移除

**异常情况**：
- PVC 被其他 Pod 使用（需要先删除 Pod）
- DataVolume 有 finalizer 但无法处理
- PVC 被其他资源引用（如其他 VirtualMachine）

---

### 4. ✅ 网络资源（可选）

**原因**：如果 NetworkAttachmentDefinition (NAD) 是由 Wukong 创建的，控制器会清理它们。

**检查方法**：
```bash
# 检查 NAD 是否存在
kubectl get networkattachmentdefinition -n default | grep your-wukong-name

# 检查 NAD 的 ownerReference
kubectl get networkattachmentdefinition <nad-name> -n default -o jsonpath='{.metadata.ownerReferences}'
```

**正常情况**：
- NAD 有正确的 ownerReference（指向 Wukong）
- NAD 没有被其他资源使用

**异常情况**：
- NAD 是用户手动创建的（不应该被删除）
- NAD 被其他资源引用

---

### 5. ✅ 没有其他阻止删除的因素

**检查方法**：
```bash
# 检查 Wukong 资源状态
kubectl get wukong <wukong-name> -n default -o yaml

# 检查是否有删除保护注解
kubectl get wukong <wukong-name> -n default -o jsonpath='{.metadata.annotations}'
```

**正常情况**：
- 没有删除保护注解（如 `kubectl.kubernetes.io/last-applied-configuration`）
- 没有其他 finalizer（除了 `wukong.novasphere.dev/finalizer`）

---

## 删除流程

正常情况下，删除 Wukong 资源的流程如下：

```
1. 用户执行：kubectl delete wukong <name>
   ↓
2. Kubernetes 设置 deletionTimestamp
   ↓
3. 控制器检测到删除标记，执行 reconcileDelete
   ↓
4. 删除 VirtualMachine（如果存在）
   ↓
5. 删除 DataVolume（如果存在）
   ↓
6. 删除 PVC（如果存在且没有 ownerReference）
   ↓
7. 等待所有资源删除完成
   ↓
8. 移除 finalizer
   ↓
9. Wukong 资源被完全删除
```

---

## 常见问题

### Q1: 删除卡在 Terminating 状态

**可能原因**：
1. 控制器未运行
2. VirtualMachine 删除失败
3. PVC 被其他资源引用
4. 网络问题导致控制器无法访问 API Server

**解决方法**：
```bash
# 1. 检查控制器状态
kubectl get pods -A | grep controller

# 2. 检查资源状态
kubectl get vm,datavolume,pvc -n default | grep <wukong-name>

# 3. 手动清理（如果控制器无法运行）
# 参考：docs/installation/cleanup-stuck-wukong.sh
```

---

### Q2: PVC 删除失败

**可能原因**：
1. PVC 被其他 Pod 使用
2. PVC 有 `kubernetes.io/pvc-protection` finalizer
3. DataVolume 删除失败

**解决方法**：
```bash
# 1. 检查 PVC 引用
kubectl get pods -A -o json | jq '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="<pvc-name>")'

# 2. 先删除 DataVolume（如果存在）
kubectl delete datavolume <dv-name> -n default

# 3. 手动移除 finalizer（如果必要）
kubectl patch pvc <pvc-name> -n default -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

### Q3: VirtualMachine 删除失败

**可能原因**：
1. KubeVirt 控制器未运行
2. VirtualMachine 有 finalizer 但无法处理
3. VMI 删除失败

**解决方法**：
```bash
# 1. 检查 KubeVirt 控制器
kubectl get pods -n kubevirt | grep virt-controller

# 2. 检查 VMI 状态
kubectl get vmi -n default | grep <vm-name>

# 3. 强制删除（如果必要）
kubectl delete vm <vm-name> -n default --force --grace-period=0
```

---

## 最佳实践

1. **删除前检查**：
   ```bash
   # 检查所有相关资源
   kubectl get wukong,vm,datavolume,pvc -n default | grep <wukong-name>
   ```

2. **优雅删除**：
   - 先停止 VM（如果正在运行）
   - 等待资源清理完成
   - 不要强制删除（除非必要）

3. **监控删除进度**：
   ```bash
   # 实时监控删除状态
   watch -n 1 'kubectl get wukong,vm,datavolume,pvc -n default | grep <wukong-name>'
   ```

4. **保留重要数据**：
   - 删除前备份重要数据
   - 考虑使用 `PreserveDisksOnDelete` 选项（如果实现）

---

## 相关文档

- [清理卡住的 Wukong 资源脚本](../installation/cleanup-stuck-wukong.sh)
- [删除功能设计文档](../interview/13.7.4-删除功能.md)

