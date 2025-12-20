# 修复 nodeSelector 调度问题

## 问题

Pod 无法调度，错误信息：
```
0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector
```

## 可能的原因

1. **KubeVirt 的 nodePlacement 配置**：KubeVirt CR 可能配置了 `infra.nodePlacement`，这会影响所有 VMI 的调度
2. **virt-launcher Pod 有默认的 nodeSelector**：KubeVirt 可能为 virt-launcher Pod 设置了默认的 nodeSelector
3. **资源不足**：虽然节点容量足够，但可能已分配的资源不足

## 排查步骤

### 1. 检查 KubeVirt 的 nodePlacement 配置

```bash
kubectl get kubevirt -n kubevirt -o yaml | grep -A 30 "nodePlacement\|infra"
```

如果看到类似配置：
```yaml
spec:
  infra:
    nodePlacement:
      nodeSelector:
        kubernetes.io/arch: amd64
```

这可能是问题所在。

### 2. 检查 virt-launcher Pod 的实际配置

```bash
POD_NAME=$(kubectl get pods -n default -o name | grep virt-launcher | head -1 | cut -d/ -f2)
kubectl get pod $POD_NAME -n default -o yaml | grep -A 20 "nodeSelector\|affinity"
```

### 3. 检查节点资源

```bash
kubectl describe node docker-desktop | grep -A 15 "Allocated resources"
```

## 解决方案

### 方案 1: 修改 KubeVirt 配置（如果 nodePlacement 是问题）

如果 KubeVirt 有 `infra.nodePlacement.nodeSelector`，需要：

1. **编辑 KubeVirt CR**：
```bash
kubectl edit kubevirt -n kubevirt kubevirt
```

2. **移除或修改 nodePlacement**：
```yaml
spec:
  infra:
    nodePlacement:
      # 移除 nodeSelector，或者设置为空
      nodeSelector: {}
      # 或者添加 tolerations 允许在 control-plane 节点调度
      tolerations:
        - effect: NoSchedule
          key: node-role.kubernetes.io/control-plane
          operator: Exists
```

### 方案 2: 在 Wukong 中添加 toleration（临时方案）

如果 KubeVirt 有默认的 nodeSelector，可以在 Wukong 中添加 toleration：

```yaml
spec:
  highAvailability:
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
```

### 方案 3: 添加节点 label（如果 nodeSelector 需要特定 label）

如果 Pod 需要特定的 node label，可以添加：

```bash
kubectl label node docker-desktop <required-label>=<value>
```

## 快速修复（推荐）

如果确认是 KubeVirt 的 nodePlacement 问题，最快的方法是：

1. **检查 KubeVirt 配置**：
```bash
kubectl get kubevirt -n kubevirt -o yaml > kubevirt-config.yaml
cat kubevirt-config.yaml | grep -A 20 "nodePlacement"
```

2. **如果看到 nodeSelector，编辑并移除**：
```bash
kubectl edit kubevirt -n kubevirt kubevirt
# 移除或注释掉 infra.nodePlacement.nodeSelector
```

3. **等待 KubeVirt 重新部署**（可能需要几分钟）

4. **删除并重新创建 Wukong**：
```bash
kubectl delete wukong ubuntu-noble-local
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

## 验证

修复后，检查 Pod 是否可以调度：

```bash
# 查看 Pod 状态
kubectl get pods -n default | grep virt-launcher

# 查看 Pod 事件
kubectl describe pod <virt-launcher-pod-name> -n default | tail -20
```

如果 Pod 状态变为 `Running`，说明问题已解决。

