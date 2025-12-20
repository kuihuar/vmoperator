# 调度问题排查指南

## 问题：Pod 无法调度

错误信息：
```
0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector
```

## 排查步骤

### 1. 检查节点状态

```bash
# 查看节点信息
kubectl get nodes

# 查看节点详细信息
kubectl describe node <node-name>

# 检查节点是否有 taint
kubectl describe node <node-name> | grep Taint
```

### 2. 检查 VMI 的调度配置

```bash
# 查看 VMI 的完整配置
kubectl get vmi ubuntu-noble-local-vm -n default -o yaml

# 检查是否有 nodeSelector
kubectl get vmi ubuntu-noble-local-vm -n default -o jsonpath='{.spec.nodeSelector}'

# 检查是否有 affinity
kubectl get vmi ubuntu-noble-local-vm -n default -o jsonpath='{.spec.affinity}'

# 检查资源请求
kubectl get vmi ubuntu-noble-local-vm -n default -o jsonpath='{.spec.domain.resources}'
```

### 3. 检查 virt-launcher Pod

```bash
# 查看 virt-launcher Pod
kubectl get pods -n default | grep virt-launcher

# 查看 Pod 的详细信息
kubectl describe pod <virt-launcher-pod-name> -n default

# 查看 Pod 的调度事件
kubectl get events -n default --sort-by='.lastTimestamp' | grep <virt-launcher-pod-name>
```

### 4. 检查资源限制

```bash
# 查看节点的资源容量
kubectl describe node <node-name> | grep -A 10 "Capacity\|Allocatable"

# 查看已使用的资源
kubectl top node <node-name>
```

## 常见原因和解决方案

### 原因 1: 资源不足

**症状**：
- 节点 CPU 或内存不足
- Pod 请求的资源超过节点可用资源

**解决方案**：
1. 减少 VM 的资源请求（CPU/内存）
2. 或者增加节点资源

**修改 Wukong YAML**：
```yaml
spec:
  cpu: 1  # 减少 CPU
  memory: 1Gi  # 减少内存
```

### 原因 2: 节点有 Taint

**症状**：
- 节点有 `NoSchedule` 或 `PreferNoSchedule` taint
- Pod 没有对应的 toleration

**解决方案**：
1. 移除节点的 taint（如果是开发环境）
2. 或者在 Wukong 中添加 toleration

**移除 taint**：
```bash
kubectl taint nodes <node-name> <taint-key>- --all
```

**添加 toleration**（在 Wukong YAML 中）：
```yaml
spec:
  highAvailability:
    tolerations:
      - key: "<taint-key>"
        operator: "Equal"
        value: "<taint-value>"
        effect: "NoSchedule"
```

### 原因 3: NodeSelector 不匹配

**症状**：
- VMI 有 nodeSelector，但节点没有对应的 label

**解决方案**：
1. 检查 Wukong 是否有 `highAvailability.nodeSelector` 配置
2. 如果有，确保节点有对应的 label
3. 或者移除 nodeSelector 配置

**检查节点 labels**：
```bash
kubectl get node <node-name> --show-labels
```

**添加 label**：
```bash
kubectl label node <node-name> <key>=<value>
```

### 原因 4: Docker Desktop 资源限制

**症状**：
- Docker Desktop 的 CPU/内存限制太低
- 无法满足 VM 的资源需求

**解决方案**：
1. 增加 Docker Desktop 的资源分配
2. Settings → Resources → 增加 CPU 和 Memory
3. 重启 Docker Desktop

### 原因 5: KubeVirt 配置问题

**症状**：
- KubeVirt 可能有默认的调度策略

**解决方案**：
1. 检查 KubeVirt 的配置
2. 查看 KubeVirt CR 的配置

```bash
kubectl get kubevirt -n kubevirt -o yaml
```

## 快速修复（Docker Desktop 环境）

如果是 Docker Desktop 环境，通常只需要：

1. **确保 Docker Desktop 有足够的资源**：
   - 至少 4GB 内存
   - 至少 2 个 CPU 核心

2. **检查并移除节点 taint**：
```bash
# 查看节点
kubectl get nodes

# 查看 taint
kubectl describe node docker-desktop | grep Taint

# 如果有 taint，移除它（仅限开发环境）
kubectl taint nodes docker-desktop node-role.kubernetes.io/control-plane:NoSchedule- --ignore-not-found
```

3. **减少 VM 资源请求**（如果资源不足）：
```yaml
spec:
  cpu: 1
  memory: 1Gi
```

4. **重新创建 Wukong**：
```bash
kubectl delete wukong ubuntu-noble-local
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

## 调试命令汇总

```bash
# 1. 查看节点状态
kubectl get nodes -o wide

# 2. 查看 VMI 状态
kubectl get vmi -A

# 3. 查看 virt-launcher Pod
kubectl get pods -A | grep virt-launcher

# 4. 查看 Pod 调度事件
kubectl get events -n default --sort-by='.lastTimestamp' | tail -20

# 5. 查看节点资源
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# 6. 查看 VMI 的完整配置
kubectl get vmi ubuntu-noble-local-vm -n default -o yaml > vmi-debug.yaml
```

## 关于 Volume Snapshot 警告

警告信息：
```
No VolumeSnapshotClass: Volume snapshots are not configured for this StorageClass [hostpath]
```

这个警告**不是阻塞问题**，只是说明 `hostpath` StorageClass 不支持 Volume Snapshot。这不会影响 VM 的正常运行，可以忽略。

如果需要支持 Volume Snapshot，需要：
1. 安装 Volume Snapshot Controller
2. 创建 VolumeSnapshotClass
3. 或者使用支持 Snapshot 的 StorageClass（如云存储）

