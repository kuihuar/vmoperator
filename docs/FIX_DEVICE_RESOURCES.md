# 修复设备资源不足问题

## 问题

Pod 无法调度，错误信息：
```
Insufficient devices.kubevirt.io/kvm
Insufficient devices.kubevirt.io/tun
Insufficient devices.kubevirt.io/vhost-net
```

## 原因

KubeVirt 需要访问虚拟化设备（KVM、TUN、vhost-net），但在 Docker Desktop 环境中，这些设备可能不可用或未正确配置。

## 解决方案

### 方案 1: 检查并配置 Docker Desktop（推荐）

Docker Desktop 需要启用嵌套虚拟化支持。检查步骤：

1. **检查 Docker Desktop 设置**：
   - Settings → General → 确保 "Use Virtualization framework" 已启用
   - Settings → Resources → 确保有足够的 CPU 和内存

2. **检查节点是否支持虚拟化**：
```bash
# 检查节点是否有虚拟化设备
kubectl describe node docker-desktop | grep -A 10 "Allocated resources"
```

3. **如果设备不可用，可能需要**：
   - 重启 Docker Desktop
   - 或者使用支持虚拟化的环境（如 Linux 主机上的 k3s）

### 方案 2: 配置 KubeVirt 使用软件模拟（不推荐，性能差）

如果无法使用硬件虚拟化，可以配置 KubeVirt 使用软件模拟，但这会严重影响性能：

1. **编辑 KubeVirt CR**：
```bash
kubectl edit kubevirt -n kubevirt kubevirt
```

2. **添加配置**：
```yaml
spec:
  configuration:
    developerConfiguration:
      useEmulation: true
```

3. **等待 KubeVirt 重新部署**

### 方案 3: 检查设备插件

KubeVirt 需要设备插件来暴露虚拟化设备。检查设备插件是否运行：

```bash
# 检查 KubeVirt 设备插件
kubectl get daemonset -n kubevirt | grep device-plugin

# 检查设备插件 Pod
kubectl get pods -n kubevirt | grep device-plugin

# 查看设备插件日志
kubectl logs -n kubevirt -l kubevirt.io=device-plugin --tail=50
```

### 方案 4: 在 Mac 上使用替代方案

在 Mac + Docker Desktop 环境中，KubeVirt 可能无法正常工作，因为：
- Docker Desktop 使用 HyperKit，不支持嵌套虚拟化
- Mac 的虚拟化框架与 Linux KVM 不兼容

**替代方案**：
1. 使用 Linux 虚拟机运行 k3s
2. 使用云环境（如 GKE、EKS）
3. 使用支持虚拟化的本地 Kubernetes（如 minikube with KVM）

## 快速检查

运行以下命令检查设备资源：

```bash
# 检查节点的设备资源
kubectl describe node docker-desktop | grep -A 20 "Allocated resources"

# 检查 KubeVirt 设备插件状态
kubectl get pods -n kubevirt | grep device-plugin

# 检查 KubeVirt 配置
kubectl get kubevirt -n kubevirt -o yaml | grep -A 10 "useEmulation"
```

## 验证

修复后，检查 Pod 是否可以调度：

```bash
kubectl get pods -n default | grep virt-launcher
kubectl describe pod <virt-launcher-pod-name> -n default | tail -20
```

如果仍然显示设备不足，可能需要：
1. 重启 Docker Desktop
2. 或者考虑使用其他 Kubernetes 环境

