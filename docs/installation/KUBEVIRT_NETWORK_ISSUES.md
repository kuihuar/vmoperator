# KubeVirt 网络实现问题分析

## 1. 根据官方文档发现的问题

参考：[KubeVirt Interfaces and Networks](https://kubevirt.io/user-guide/network/interfaces_and_networks/#)

### 1.1 关键限制：macvlan 不能用于 bridge interfaces

**官方文档明确说明：**

> The following list of CNIs is known **not** to work for bridge interfaces - which are most common for secondary interfaces:
> - macvlan
> - ipvlan

**原因：**
- Bridge interface 会把 pod interface 的 MAC 地址移到 VM
- macvlan/ipvlan 需要 pod interface 保持原始 MAC 地址
- 两者冲突，无法同时使用

**当前项目问题：**
- ✅ 支持 macvlan 类型
- ✅ 但使用 `bridge` binding（`InterfaceBridge{}`）
- ❌ **这会导致 macvlan 无法正常工作！**

### 1.2 Network 和 Interface 名称不匹配

**官方文档要求：**
> Each interface must have a corresponding network with the same name.

**当前实现问题：**
- Network 使用 `net.NADName` 作为名称
- Interface 也使用 `net.NADName` 作为名称
- 但应该使用 `net.Name`（网络配置中的名称）

**示例：**
```go
// 当前实现（错误）
Network: { Name: "ubuntu-vm-external-nad" }  // 使用 NADName
Interface: { Name: "ubuntu-vm-external-nad" } // 使用 NADName

// 应该（正确）
Network: { Name: "external" }  // 使用网络配置中的名称
Interface: { Name: "external" } // 使用网络配置中的名称
```

### 1.3 buildNetworkAnnotations 可能不需要

**官方文档显示：**
- KubeVirt 会自动处理 Multus 网络
- 只需要在 `networks` 和 `interfaces` 中正确配置
- 不需要手动添加 `k8s.v1.cni.cncf.io/networks` annotation

**当前实现：**
- `buildNetworkAnnotations` 函数手动添加 annotation
- 可能是不必要的，或者与 KubeVirt 自动处理冲突

## 2. 需要修复的问题

### 2.1 移除或修正 macvlan 支持

**选项 1：移除 macvlan 支持**
- 因为 macvlan 不能用于 bridge interfaces
- 只支持 bridge 类型

**选项 2：macvlan 使用不同的 binding**
- 但文档没有说明 macvlan 应该使用什么 binding
- 可能需要使用 passthrough 或其他方式

**选项 3：macvlan 使用不同的 CNI 配置**
- 不使用 bridge CNI
- 直接使用 macvlan CNI（但文档说这不可行）

### 2.2 修复 Network 和 Interface 名称

**修复方案：**
```go
// buildNetworks
Network: {
    Name: net.Name,  // 使用网络配置中的名称
    Multus: { NetworkName: net.NADName }  // NAD 名称用于 Multus 引用
}

// buildInterfaces
Interface: {
    Name: net.Name,  // 使用网络配置中的名称，与 Network 匹配
    Bridge: {}
}
```

### 2.3 移除 buildNetworkAnnotations

**如果 KubeVirt 自动处理，可以移除：**
- `buildNetworkAnnotations` 函数
- 相关的 annotation 设置

## 3. 正确的实现方式

### 3.1 Network 配置

```go
// 默认网络
Network: {
    Name: "default",
    Pod: {}
}

// Multus 网络
Network: {
    Name: "external",  // 使用网络配置中的名称
    Multus: {
        NetworkName: "ubuntu-vm-external-nad"  // 引用 NAD 名称
    }
}
```

### 3.2 Interface 配置

```go
// 默认接口
Interface: {
    Name: "default",  // 与 Network 名称匹配
    Masquerade: {}
}

// Multus 接口
Interface: {
    Name: "external",  // 与 Network 名称匹配
    Bridge: {}  // 对于 bridge CNI 使用 Bridge binding
}
```

### 3.3 支持的 CNI 类型

根据文档，对于 bridge interfaces，应该使用：
- ✅ **bridge CNI** - 支持
- ✅ **ptp CNI** - 可能支持
- ✅ **sriov-cni** - 支持（使用 SR-IOV binding）
- ❌ **macvlan CNI** - 不支持
- ❌ **ipvlan CNI** - 不支持

## 4. 建议的修复方案

### 4.1 立即修复

1. **修复 Network 和 Interface 名称匹配**
2. **移除或警告 macvlan 支持**
3. **移除 buildNetworkAnnotations（如果不需要）**

### 4.2 长期方案

1. **只支持 bridge 类型**（最安全）
2. **或者研究 macvlan 的正确使用方式**
3. **添加 SR-IOV 支持**

## 5. 参考

- [KubeVirt Interfaces and Networks](https://kubevirt.io/user-guide/network/interfaces_and_networks/#)
- [Invalid CNIs for secondary networks](https://kubevirt.io/user-guide/network/interfaces_and_networks/#invalid-cnis-for-secondary-networks)

