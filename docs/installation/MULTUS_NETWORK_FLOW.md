# Multus 网络配置流程图

## 整体流程

```
Wukong Controller Reconcile
    ↓
1. ReconcileNetworks (pkg/network/multus.go)
    ├─ 遍历 vmp.Spec.Networks
    ├─ 跳过 "default" 网络
    ├─ 创建/获取 NetworkAttachmentDefinition (NAD)
    │   ├─ 如果不存在，自动创建
    │   └─ buildCNIConfig() 生成 CNI 配置
    │       ├─ macvlan 类型：设置 master, mode, IPAM
    │       └─ 静态 IP：使用 host-local IPAM
    └─ 返回 NetworkStatus[] (Name, NADName, MACAddress为空)
    ↓
2. ReconcileVirtualMachine (pkg/kubevirt/vm.go)
    ├─ buildVirtualMachine()
    │   └─ buildVMSpec()
    │       ├─ buildNetworks() - 构建 KubeVirt Network 列表
    │       ├─ buildInterfaces() - 构建 KubeVirt Interface 列表
    │       └─ buildCloudInitData() - 构建 Cloud-Init 配置 ⚠️
    │           ├─ 遍历 vmp.Spec.Networks
    │           ├─ 过滤：只处理 static IP 配置
    │           ├─ 跳过：default 网络或没有 NADName 的网络
    │           ├─ 尝试获取 MAC 地址：
    │           │   ├─ 从 NetworkStatus.MACAddress (通常为空)
    │           │   └─ 从现有 VMI.Status.Interfaces (首次创建时 VMI 不存在)
    │           └─ 生成 Cloud-Init network 配置
    │               ├─ 如果 MAC 地址可用：使用 MAC 匹配
    │               └─ 否则：使用 enp2s0, enp3s0 等接口名称
    └─ 创建/更新 VirtualMachine
    ↓
3. KubeVirt 创建 VMI
    ├─ Multus 根据 NAD 创建网络接口
    ├─ KubeVirt 创建 bridge 连接接口到 VM
    └─ VM 启动，Cloud-Init 执行网络配置
```

## 问题分析

### 当前问题

**现象：** Cloud-Init 配置中只有 `enp1s0`（default 网络），没有 `enp2s0`（Multus 网络）

**根本原因：**

1. **Cloud-Init 配置条件判断问题**
   ```go
   // 在 buildCloudInitData 中
   if vmp.Spec.OSImage != "" || vmp.Spec.SSHKeySecret != "" || vmp.Spec.CloudInitUser != nil {
       cloudInitData := buildCloudInitData(ctx, c, vmp, networks)
   }
   ```
   - 如果 `CloudInitUser` 为 nil，但网络需要配置，Cloud-Init 不会被调用
   - **问题：** 网络配置依赖于用户配置的存在

2. **MAC 地址获取时机问题**
   - 首次创建 VM 时，VMI 不存在，无法获取 MAC 地址
   - NetworkStatus.MACAddress 在创建时为空的（注释说明需要在 VM 运行后填充）
   - Fallback 逻辑应该使用 `enp2s0`，但配置没有生成

3. **接口名称不匹配**
   - Cloud-Init 配置使用 `eth1` 或 `enp2s0`
   - 但实际 VM 内部接口名称可能不同
   - 需要确认 VM 内部的接口名称

## 流程图

### 详细流程图

```
┌─────────────────────────────────────────────────────────────┐
│ Wukong Controller Reconcile                                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. ReconcileNetworks()                                       │
│    pkg/network/multus.go                                     │
│                                                               │
│    for each network in vmp.Spec.Networks:                    │
│      ├─ if network.Name == "default":                        │
│      │    └─ skip (使用 Pod 网络)                            │
│      │                                                       │
│      ├─ 生成 NAD 名称: {wukong-name}-{network-name}-nad     │
│      ├─ 检查 NAD 是否存在                                    │
│      │                                                       │
│      ├─ if NAD 不存在:                                       │
│      │    ├─ buildCNIConfig()                                │
│      │    │   ├─ macvlan: master=ens160, mode=bridge        │
│      │    │   └─ IPAM: host-local (static IP)                │
│      │    │       ├─ subnet: 192.168.1.0/24                 │
│      │    │       ├─ rangeStart: 192.168.1.200               │
│      │    │       └─ rangeEnd: 192.168.1.200                │
│      │    └─ 创建 NAD                                        │
│      │                                                       │
│      └─ 返回 NetworkStatus{                                  │
│           Name: "external",                                  │
│           NADName: "ubuntu-rulai-multus-external-nad",      │
│           MACAddress: ""  ⚠️ 创建时为空                     │
│         }                                                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. ReconcileVirtualMachine()                                 │
│    pkg/kubevirt/vm.go                                        │
│                                                               │
│    buildVirtualMachine()                                     │
│      └─ buildVMSpec()                                        │
│          ├─ buildNetworks()                                  │
│          │   └─ 创建 KubeVirt Network 列表                   │
│          │       ├─ default: Pod network                    │
│          │       └─ ubuntu-rulai-multus-external-nad: Multus│
│          │                                                   │
│          ├─ buildInterfaces()                               │
│          │   └─ 创建 KubeVirt Interface 列表                  │
│          │       ├─ default: masquerade                      │
│          │       └─ ubuntu-rulai-multus-external-nad: bridge│
│          │                                                   │
│          └─ buildCloudInitData() ⚠️ 关键问题在这里           │
│              │                                               │
│              ├─ 条件检查:                                    │
│              │   if OSImage || SSHKeySecret || CloudInitUser │
│              │   └─ 只有满足条件才生成 Cloud-Init            │
│              │                                               │
│              ├─ 网络配置部分:                                │
│              │   for each network in vmp.Spec.Networks:      │
│              │     if IPConfig.Mode == "static":            │
│              │       if network.Name == "default":           │
│              │         continue  ⚠️ 跳过                     │
│              │       if netStatus.NADName == "":             │
│              │         continue  ⚠️ 跳过                     │
│              │                                               │
│              │       # 尝试获取 MAC 地址                     │
│              │       macAddress = ""                         │
│              │       if netStatus.MACAddress != "":         │
│              │         macAddress = netStatus.MACAddress    │
│              │       else:                                   │
│              │         # 尝试从 VMI 获取                     │
│              │         vmi = Get VMI                         │
│              │         if vmi exists:                        │
│              │           for iface in vmi.Status.Interfaces: │
│              │             if iface.Name == NADName:         │
│              │               macAddress = iface.MAC           │
│              │                                               │
│              │       # 生成 Cloud-Init 配置                  │
│              │       if macAddress != "":                   │
│              │         使用 MAC 匹配: enp2s0                  │
│              │       else:                                  │
│              │         使用接口名称: enp2s0                   │
│              │                                               │
│              │       添加 IP 配置: 192.168.1.200/24         │
│              │       添加网关: 192.168.1.1                   │
│              │       添加 DNS: 192.168.1.1, 114.114.114.114  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. KubeVirt 创建 VMI                                         │
│                                                               │
│    Multus 根据 NAD 创建网络接口:                            │
│      ├─ 在 Pod 网络命名空间中创建 macvlan 接口               │
│      ├─ KubeVirt 创建 bridge (k6t-xxx)                      │
│      └─ 连接 macvlan 接口到 bridge                           │
│                                                               │
│    VM 启动:                                                   │
│      ├─ Cloud-Init 执行网络配置                              │
│      ├─ 如果配置正确：enp2s0 应该配置 IP                     │
│      └─ 如果配置错误：enp2s0 保持 DOWN 状态                   │
└─────────────────────────────────────────────────────────────┘
```

## 关键问题点

### 问题 1: Cloud-Init 配置条件

**代码位置：** `pkg/kubevirt/vm.go:137`

```go
if vmp.Spec.OSImage != "" || vmp.Spec.SSHKeySecret != "" || vmp.Spec.CloudInitUser != nil {
    cloudInitData := buildCloudInitData(ctx, c, vmp, networks)
}
```

**问题：** 如果只有网络配置需要 Cloud-Init，但用户配置为空，Cloud-Init 不会被生成。

**解决方案：** 修改条件，只要有静态 IP 配置就生成 Cloud-Init。

### 问题 2: MAC 地址获取时机

**代码位置：** `pkg/kubevirt/vm.go:447-464`

**问题：**
- 首次创建 VM 时，VMI 不存在，无法获取 MAC 地址
- NetworkStatus.MACAddress 在创建时为空
- Fallback 逻辑应该工作，但可能没有执行

**解决方案：** 确保 fallback 逻辑正确执行，即使 MAC 地址不可用也生成配置。

### 问题 3: 接口名称匹配

**当前实现：** 使用 `enp2s0` 作为接口名称

**问题：** VM 内部的接口名称可能不是 `enp2s0`

**解决方案：** 使用 MAC 地址匹配（需要从 VMI 获取）或使用通配符匹配。

## 修复建议

### 修复 1: 修改 Cloud-Init 生成条件

```go
// 修改前
if vmp.Spec.OSImage != "" || vmp.Spec.SSHKeySecret != "" || vmp.Spec.CloudInitUser != nil {
    cloudInitData := buildCloudInitData(ctx, c, vmp, networks)
}

// 修改后
hasStaticIP := false
for _, net := range vmp.Spec.Networks {
    if net.IPConfig != nil && net.IPConfig.Mode == "static" && net.IPConfig.Address != nil {
        hasStaticIP = true
        break
    }
}

if vmp.Spec.OSImage != "" || vmp.Spec.SSHKeySecret != "" || 
   vmp.Spec.CloudInitUser != nil || hasStaticIP {
    cloudInitData := buildCloudInitData(ctx, c, vmp, networks)
}
```

### 修复 2: 确保网络配置总是生成

在 `buildCloudInitData` 中，确保即使 MAC 地址不可用，也生成网络配置：

```go
// 当前代码已经有 fallback，但需要确保执行
if macAddress != "" {
    // 使用 MAC 匹配
} else {
    // 使用接口名称匹配 - 这应该总是执行
    cloudInit += fmt.Sprintf("    enp%ds0:\n", multusInterfaceIndex+1)
}
```

### 修复 3: 使用更灵活的接口匹配

考虑使用通配符或从 VMI 状态获取接口名称：

```go
// 选项 1: 使用通配符
cloudInit += "    enp*:\n"
cloudInit += "      match:\n"
cloudInit += fmt.Sprintf("        macaddress: %s\n", macAddress)

// 选项 2: 从 VMI 获取接口名称（如果可用）
if vmi != nil {
    for _, iface := range vmi.Status.Interfaces {
        if iface.Name == netStatus.NADName {
            interfaceName = iface.InterfaceName
            break
        }
    }
}
```

## 验证步骤

1. **检查 Cloud-Init 配置是否生成**
   ```bash
   kubectl get vm ubuntu-rulai-multus-vm -o yaml | grep -A 50 "userdata:"
   ```

2. **检查 VM 内部接口**
   ```bash
   ssh ubuntu@<POD_IP>
   ip addr show
   ```

3. **检查 Cloud-Init 日志**
   ```bash
   kubectl logs <virt-launcher-pod> -c guest-console-log | grep -i network
   ```

## 总结

当前实现的主要问题：
1. Cloud-Init 生成条件可能不满足（需要检查）
2. MAC 地址在首次创建时不可用（正常，但 fallback 应该工作）
3. 接口名称可能不匹配（需要确认 VM 内部的实际接口名称）

建议先检查 Cloud-Init 配置是否真的生成了网络部分，如果没有，修复生成条件。


