# 重构后测试指南

## 1. 检查控制器运行状态

确保 `make run` 没有 panic 错误，应该看到类似输出：

```
INFO	starting manager
INFO	Starting Controller	{"controller": "wukong"}
INFO	Starting workers	{"controller": "wukong", "worker count": 1}
```

## 2. 检查 Wukong 资源状态

```bash
# 查看 Wukong 资源
kubectl get wukong ubuntu-noble-local

# 查看详细信息
kubectl describe wukong ubuntu-noble-local

# 查看完整 YAML（包括 status）
kubectl get wukong ubuntu-noble-local -o yaml
```

**预期状态**：
- `STATUS.phase` 应该从 `Creating` 变为 `Running`
- `STATUS.conditions` 应该显示 `Ready=True`, `NetworksConfigured=True`, `VolumesBound=True`

## 3. 检查 VirtualMachine（KubeVirt）

```bash
# 查看 VirtualMachine
kubectl get vm -A

# 查看详细信息
kubectl describe vm ubuntu-noble-local-vm -n default

# 查看完整 YAML
kubectl get vm ubuntu-noble-local-vm -n default -o yaml
```

**预期状态**：
- 应该能看到 `ubuntu-noble-local-vm`
- `STATUS.ready` 应该为 `true`
- `STATUS.created` 应该为 `true`

## 4. 检查 VirtualMachineInstance（运行中的 VM）

```bash
# 查看 VirtualMachineInstance
kubectl get vmi -A

# 查看详细信息
kubectl describe vmi ubuntu-noble-local-vm -n default

# 查看完整 YAML
kubectl get vmi ubuntu-noble-local-vm -n default -o yaml
```

**预期状态**：
- 应该能看到 `ubuntu-noble-local-vm`
- `STATUS.phase` 应该为 `Running`
- `STATUS.nodeName` 应该显示运行在哪个节点上
- `STATUS.interfaces` 应该显示网络接口信息

## 5. 检查存储资源

```bash
# 查看 DataVolume
kubectl get datavolume -A

# 查看 PVC
kubectl get pvc -A

# 查看 DataVolume 详细信息
kubectl describe datavolume ubuntu-noble-local-system -n default

# 查看 PVC 详细信息
kubectl describe pvc ubuntu-noble-local-system -n default
```

**预期状态**：
- DataVolume 的 `PHASE` 应该为 `Succeeded`
- PVC 的 `STATUS` 应该为 `Bound`
- PVC 应该有 `VOLUME` 和 `CAPACITY` 信息

## 6. 检查 Pod（CDI importer 和 VM Pod）

```bash
# 查看所有 Pod
kubectl get pods -A

# 查看 importer Pod（如果还在运行）
kubectl get pods -A | grep importer

# 查看 virt-launcher Pod（VM 的实际 Pod）
kubectl get pods -A | grep virt-launcher
```

**预期状态**：
- `importer-ubuntu-noble-local-system` 应该已经完成（Completed 或不存在）
- `virt-launcher-ubuntu-noble-local-vm-*` 应该为 `Running`

## 7. 验证 VM 网络连接（可选）

如果 VM 已经运行，可以尝试连接到 VM：

```bash
# 获取 VMI 的 IP 地址
kubectl get vmi ubuntu-noble-local-vm -n default -o jsonpath='{.status.interfaces[0].ipAddress}'

# 或者查看完整网络信息
kubectl get vmi ubuntu-noble-local-vm -n default -o jsonpath='{.status.interfaces[*]}' | jq
```

## 8. 查看控制器日志

如果遇到问题，查看 `make run` 的日志输出，应该能看到：

```
INFO	Reconciling Wukong	{"name": "ubuntu-noble-local"}
INFO	Reconciling VirtualMachine	{"name": "ubuntu-noble-local-vm"}
INFO	Creating VirtualMachine	{"name": "ubuntu-noble-local-vm"}
INFO	Successfully created VirtualMachine	{"name": "ubuntu-noble-local-vm"}
```

## 常见问题排查

### 问题 1: Wukong 一直处于 Creating 状态

**检查**：
```bash
# 查看 Wukong 的 events
kubectl describe wukong ubuntu-noble-local

# 查看控制器日志中的错误
# 在 make run 的输出中查找 ERROR
```

### 问题 2: VirtualMachine 未创建

**检查**：
```bash
# 查看是否有权限问题
kubectl auth can-i create virtualmachines.kubevirt.io -n default

# 查看 KubeVirt 是否安装
kubectl get crd virtualmachines.kubevirt.io
```

### 问题 3: DataVolume 一直处于 Pending 状态

**检查**：
```bash
# 查看 DataVolume 的 events
kubectl describe datavolume ubuntu-noble-local-system

# 查看 importer Pod 的状态
kubectl describe pod importer-ubuntu-noble-local-system -n default
```

### 问题 4: VMI 无法启动

**检查**：
```bash
# 查看 VMI 的 events
kubectl describe vmi ubuntu-noble-local-vm

# 查看 virt-launcher Pod 的日志
kubectl logs -n default virt-launcher-ubuntu-noble-local-vm-* --tail=100
```

## 成功标志

如果一切正常，你应该看到：

1. ✅ `kubectl get wukong` 显示 `STATUS` 为 `Running`
2. ✅ `kubectl get vm` 显示 VirtualMachine 已创建
3. ✅ `kubectl get vmi` 显示 VirtualMachineInstance 为 `Running`
4. ✅ `kubectl get pvc` 显示 PVC 为 `Bound`
5. ✅ `kubectl get pods` 显示 `virt-launcher-*` Pod 为 `Running`
6. ✅ 控制器日志中没有 ERROR 或 panic

## 下一步

如果所有检查都通过，说明重构成功！你可以：

1. 尝试创建更多的 Wukong 资源
2. 测试不同的配置（多网络、多磁盘等）
3. 测试 VM 的启动、停止、删除等操作
4. 继续开发其他功能

