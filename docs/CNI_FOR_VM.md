# CNI 对虚拟机启动的影响

## 问题：没有安装 Flannel/Calico/Cilium 是否影响启动虚拟机？

### 简短回答

**如果 Wukong 资源中没有配置 `networks`（多网卡），不影响启动虚拟机。**

### 详细说明

#### 1. k3s 默认包含 Flannel

k3s 默认内置 Flannel CNI，即使没有看到 Flannel Pod，网络功能通常也是可用的。k3s 的 Flannel 可能以不同方式运行（如作为 k3s 的一部分，而不是独立的 Pod）。

#### 2. 虚拟机网络需求

**对于 KubeVirt 虚拟机：**

- **默认 Pod 网络**：每个 VM 至少需要一个网络接口，KubeVirt 默认使用 Pod 网络
- **多网卡**：如果 Wukong 资源中配置了 `networks`（多网卡），需要 Multus CNI
- **单网卡**：如果 Wukong 资源中没有 `networks` 配置，只使用默认 Pod 网络，**不需要 Multus**

#### 3. 检查当前网络状态

```bash
# 检查 k3s 网络是否工作
kubectl get pods -A
kubectl get svc

# 检查是否有网络插件（可能以不同名称运行）
kubectl get pods -A | grep -E "flannel|calico|cilium|network"

# 检查 k3s 的 CNI 配置
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/ 2>/dev/null
```

#### 4. 对虚拟机启动的影响

**场景 A：Wukong 资源中没有 `networks` 配置**

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
spec:
  # 没有 networks 配置
  disks:
    - name: system
      size: 10Gi
```

- ✅ **可以启动**：使用默认 Pod 网络
- ✅ **不需要 Multus**
- ✅ **不需要额外的 CNI 插件**（k3s 内置的即可）

**场景 B：Wukong 资源中配置了 `networks`（多网卡）**

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
spec:
  networks:
    - name: net1
      type: bridge
  disks:
    - name: system
      size: 10Gi
```

- ⚠️ **需要 Multus**：多网卡需要 Multus CNI
- ⚠️ **需要主 CNI**：Multus 需要找到主 CNI（如 Flannel）
- ❌ **如果 Multus 未正确配置，VM 可能无法启动**

## 建议

### 如果当前 Wukong 资源没有配置 networks

1. **可以跳过 Multus 配置**：不需要修复 Multus
2. **直接测试 VM 启动**：
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   kubectl get wukong
   kubectl get vm
   kubectl get vmi
   ```
3. **如果 VM 能启动**：说明网络正常，可以继续使用

### 如果将来需要多网卡功能

1. 先确保 k3s 网络正常工作
2. 修复 Multus 配置（使用正确的 k3s CNI 路径）
3. 然后在 Wukong 资源中添加 `networks` 配置

## 验证网络是否工作

```bash
# 1. 检查 Pod 是否能正常创建和通信
kubectl run test-pod --image=busybox --rm -it -- ping -c 3 8.8.8.8

# 2. 检查 Service 是否正常
kubectl get svc

# 3. 如果以上都正常，说明网络工作正常，可以启动 VM
```

## 总结

- **没有安装独立的 Flannel/Calico/Cilium Pod**：不影响（k3s 内置）
- **Wukong 资源没有 networks 配置**：不影响启动 VM
- **Wukong 资源有 networks 配置**：需要 Multus，需要修复 Multus 配置

**建议**：先测试启动 VM，如果成功，说明网络正常，可以暂时跳过 Multus 配置。

