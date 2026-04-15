# 创建/更新桥接网络策略详细说明

## 1. 概述

`reconcileBridgePolicy` 函数负责创建或更新 `NodeNetworkConfigurationPolicy` 资源，用于在节点上创建 Linux 桥接，并将物理网卡连接到桥接上。

## 2. 函数流程

### 2.1 函数签名

```go
func reconcileBridgePolicy(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, netCfg *vmv1alpha1.NetworkConfig) error
```

**参数说明**：
- `ctx`: 上下文，用于取消和超时控制
- `c`: Kubernetes API 客户端
- `vmp`: Wukong 自定义资源
- `netCfg`: 网络配置，包含桥接名称、物理网卡等信息

### 2.2 完整流程

```
开始
  ↓
1. 生成策略名称：{wukong-name}-{network-name}-bridge
  ↓
2. 确定桥接名称（如果未指定，使用默认：br-{network-name}）
  ↓
3. 验证物理网卡名称（必须指定）
  ↓
4. 检查 VLANID（暂时不支持，如果指定则返回错误）
  ↓
5. 从 NodeNetworkState 获取物理网卡的 IP 配置信息
  ↓
6. 验证 IP 地址格式（静态 IP 模式时）
  ↓
7. 构建 NodeNetworkConfigurationPolicy 对象
  ↓
8. 创建或更新策略
  ↓
结束
```

## 3. 详细步骤说明

### 步骤 1-3：基本参数准备

```go
// 生成策略名称
policyName := fmt.Sprintf("%s-%s-bridge", vmp.Name, netCfg.Name)

// 确定桥接名称
bridgeName := netCfg.BridgeName
if bridgeName == "" {
    bridgeName = fmt.Sprintf("br-%s", netCfg.Name)
}

// 验证物理网卡名称
physicalInterface := netCfg.PhysicalInterface
if physicalInterface == "" {
    return fmt.Errorf("physicalInterface is required for bridge/ovs network type")
}
```

**说明**：
- 策略名称格式：`{wukong名称}-{网络名称}-bridge`
  - 例如：`ubuntu-vm-external-bridge`
- 桥接名称：如果未指定，使用默认名称 `br-{网络名称}`
  - 例如：`br-external`
- 物理网卡名称必须明确指定，例如：`ens192`

### 步骤 4：VLAN 检查

```go
if netCfg.VLANID != nil {
    logger.Error(nil, "VLAN is not supported yet", ...)
    return fmt.Errorf("VLAN configuration is not supported yet")
}
```

**说明**：
- 当前版本不支持 VLAN
- 如果配置了 VLANID，直接返回错误

### 步骤 5：获取物理网卡 IP 配置

```go
ipInfo, err := getIPConfigFromNodeNetworkState(ctx, c, physicalInterface)
if err != nil {
    return fmt.Errorf("failed to get IP config from NodeNetworkState for interface %s: %w", physicalInterface, err)
}
```

**功能**：
- 从 `NodeNetworkState` 资源中获取物理网卡的 IP 配置信息
- 返回 `ipConfigInfo` 结构，包含：
  - `ipAddress`: IP 地址（格式：`192.168.0.105/24`）
  - `useDHCP`: 是否使用 DHCP（`true`/`false`）

**为什么需要这一步**：
- 需要知道物理网卡当前使用的 IP 配置方式（DHCP 或静态 IP）
- 桥接必须使用相同的 IP 配置方式，才能保证节点网络不中断

**数据来源**：
- 查询所有 `NodeNetworkState` 资源
- 在 `status.currentState.interfaces[]` 中查找匹配的接口名称
- 提取 `ipv4.dhcp` 和 `ipv4.address[0]` 信息

### 步骤 6：验证 IP 地址格式

```go
useDHCP := ipInfo.useDHCP
if !useDHCP {
    if ipInfo.ipAddress == "" {
        return fmt.Errorf("static IP mode but no IP address found in NodeNetworkState")
    }
    _, _, err := parseIPAddress(ipInfo.ipAddress)
    if err != nil {
        return fmt.Errorf("invalid IP address format from NodeNetworkState")
    }
}
```

**功能**：
- 如果是静态 IP 模式，验证 IP 地址是否存在
- 验证 IP 地址格式是否正确（CIDR 格式：`192.168.0.105/24`）
- 如果验证失败，直接返回错误（不会降级处理）

### 步骤 7：构建 NodeNetworkConfigurationPolicy

#### 7.1 创建策略对象

```go
nncp := &unstructured.Unstructured{}
nncp.SetGroupVersionKind(schema.GroupVersionKind{
    Group:   "nmstate.io",
    Version: "v1",
    Kind:    "NodeNetworkConfigurationPolicy",
})
nncp.SetName(policyName)
// 注意：NodeNetworkConfigurationPolicy 是集群级别资源，没有命名空间
```

**说明**：
- 使用 `unstructured.Unstructured` 类型（因为 NMState 没有官方 Go 客户端）
- 设置资源类型为 `NodeNetworkConfigurationPolicy`
- 策略名称已在前面的步骤中确定
- 这是集群级别资源，不设置命名空间

#### 7.2 构建 desiredState

```go
desiredState := map[string]interface{}{
    "interfaces": []interface{}{},
}
interfaces := []interface{}{}
```

#### 7.3 构建桥接接口配置

```go
bridgeInterface := map[string]interface{}{
    "name":  bridgeName,
    "type":  "linux-bridge",
    "state": "up",
    "bridge": map[string]interface{}{
        "options": map[string]interface{}{
            "stp": map[string]interface{}{
                "enabled": false,  // 禁用 STP（生成树协议）
            },
        },
        "port": []interface{}{
            map[string]interface{}{
                "name": physicalInterface,  // 物理网卡作为桥接端口
            },
        },
    },
}
```

**说明**：
- `name`: 桥接名称（如 `br-external`）
- `type`: `linux-bridge`（Linux 桥接）
- `state`: `up`（启用状态）
- `bridge.options.stp.enabled`: `false`（禁用 STP，简化配置）
- `bridge.port[].name`: 物理网卡名称（如 `ens192`）

#### 7.4 配置桥接 IP

**情况 1：DHCP 模式**

```go
if useDHCP {
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "dhcp":    true,
    }
}
```

**情况 2：静态 IP 模式**

```go
else {
    ip, prefixLen, err := parseIPAddress(ipInfo.ipAddress)
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "dhcp":    false,
        "address": []interface{}{
            map[string]interface{}{
                "ip":            ip,           // 例如："192.168.0.105"
                "prefix-length": int64(prefixLen),  // 例如：24
            },
        },
    }
}
```

**关键点**：
- 桥接使用与物理网卡相同的 IP 配置方式
- 如果物理网卡使用 DHCP，桥接也使用 DHCP
- 如果物理网卡使用静态 IP，桥接也使用相同的静态 IP
- 这样确保节点网络不中断

#### 7.5 配置物理网卡（禁用 IP）

```go
physicalInterfaceConfig := map[string]interface{}{
    "name":  physicalInterface,
    "type":  "ethernet",
    "state": "up",
    "ipv4": map[string]interface{}{
        "enabled": false,  // 禁用物理网卡的 IP（IP 在桥接上）
    },
}
interfaces = append(interfaces, physicalInterfaceConfig)
```

**为什么需要这一步**：
- NMState 采用声明式配置，必须明确指定每个接口的状态
- 当物理网卡被添加到桥接时，如果不明确配置，NMState 可能会移除物理网卡的 IP
- 明确禁用物理网卡的 IP，因为 IP 已经迁移到桥接上

#### 7.6 组装接口列表

```go
interfaces = append(interfaces, bridgeInterface)
desiredState["interfaces"] = interfaces
```

**接口顺序**：
1. 桥接接口（`bridgeInterface`）
2. 物理网卡接口（`physicalInterfaceConfig`）

### 步骤 8：创建或更新策略

```go
// 设置 spec
if err := unstructured.SetNestedField(nncp.Object, desiredState, "spec", "desiredState"); err != nil {
    return fmt.Errorf("failed to set desiredState: %w", err)
}

// 尝试获取现有的策略
existingNNCP := &unstructured.Unstructured{}
existingNNCP.SetGroupVersionKind(schema.GroupVersionKind{
    Group:   "nmstate.io",
    Version: "v1",
    Kind:    "NodeNetworkConfigurationPolicy",
})
key := client.ObjectKey{Name: policyName}

err := c.Get(ctx, key, existingNNCP)
if err != nil {
    if errors.IsNotFound(err) {
        // 创建新策略
        logger.Info("Creating NodeNetworkConfigurationPolicy", "name", policyName)
        if err := c.Create(ctx, nncp); err != nil {
            return fmt.Errorf("failed to create NodeNetworkConfigurationPolicy: %w", err)
        }
    } else {
        return fmt.Errorf("failed to get NodeNetworkConfigurationPolicy: %w", err)
    }
} else {
    // 更新现有策略
    logger.V(1).Info("Updating NodeNetworkConfigurationPolicy", "name", policyName)
    existingNNCP.Object["spec"] = nncp.Object["spec"]
    if err := c.Update(ctx, existingNNCP); err != nil {
        return fmt.Errorf("failed to update NodeNetworkConfigurationPolicy: %w", err)
    }
}
```

**逻辑**：
1. 将 `desiredState` 设置到策略的 `spec.desiredState` 字段
2. 尝试获取现有的策略
3. 如果不存在（`NotFound`），创建新策略
4. 如果存在，更新现有策略的 `spec` 字段

## 4. 生成的 NodeNetworkConfigurationPolicy 示例

### 4.1 DHCP 模式

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ubuntu-vm-external-bridge
spec:
  desiredState:
    interfaces:
    - name: br-external
      type: linux-bridge
      state: up
      bridge:
        options:
          stp:
            enabled: false
        port:
        - name: ens192
      ipv4:
        enabled: true
        dhcp: true
    - name: ens192
      type: ethernet
      state: up
      ipv4:
        enabled: false
```

### 4.2 静态 IP 模式

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ubuntu-vm-external-bridge
spec:
  desiredState:
    interfaces:
    - name: br-external
      type: linux-bridge
      state: up
      bridge:
        options:
          stp:
            enabled: false
        port:
        - name: ens192
      ipv4:
        enabled: true
        dhcp: false
        address:
        - ip: 192.168.0.105
          prefix-length: 24
    - name: ens192
      type: ethernet
      state: up
      ipv4:
        enabled: false
```

## 5. 关键设计原则

### 5.1 IP 配置一致性

**原则**：桥接必须使用与物理网卡相同的 IP 配置方式（DHCP 或静态 IP）

**原因**：
- 物理网卡的 IP 会迁移到桥接上
- 如果配置不一致，可能导致节点网络中断
- 例如：物理网卡是 DHCP，但桥接配置为静态 IP → IP 冲突
- 例如：物理网卡是静态 IP，但桥接配置为 DHCP → 节点可能失去网络连接

### 5.2 声明式配置

**原则**：必须明确指定每个接口的状态

**原因**：
- NMState 采用声明式配置模型
- 如果不明确配置物理网卡的状态，NMState 可能会移除物理网卡的 IP
- 因此必须明确禁用物理网卡的 IP（`ipv4.enabled: false`）

### 5.3 自动检测优先

**原则**：优先从 NodeNetworkState 自动检测 IP 配置

**原因**：
- 自动检测更可靠，能适应网络配置的变化
- 减少用户配置负担
- 确保配置与实际网络状态一致

## 6. 错误处理

### 6.1 物理网卡未指定

```go
if physicalInterface == "" {
    return fmt.Errorf("physicalInterface is required for bridge/ovs network type")
}
```

### 6.2 无法获取 IP 配置

```go
if err != nil {
    return fmt.Errorf("failed to get IP config from NodeNetworkState for interface %s: %w", physicalInterface, err)
}
```

**可能原因**：
- NodeNetworkState 资源不存在
- 指定的接口名称不存在
- 接口没有 IP 配置

### 6.3 静态 IP 但 IP 地址无效

```go
if ipInfo.ipAddress == "" {
    return fmt.Errorf("static IP mode but no IP address found in NodeNetworkState")
}
if err != nil {
    return fmt.Errorf("invalid IP address format from NodeNetworkState")
}
```

## 7. 执行后的效果

### 7.1 节点网络变化

**执行前**：
```
ens192: 192.168.0.105/24 (静态 IP 或 DHCP)
```

**执行后**：
```
br-external: 192.168.0.105/24 (静态 IP 或 DHCP)
  └─ ens192 (端口，IP 已禁用)
```

### 7.2 NMState Operator 的工作

1. **监控策略**：NMState Operator 监控 `NodeNetworkConfigurationPolicy` 资源
2. **应用配置**：将 `spec.desiredState` 应用到节点网络
3. **创建桥接**：创建 Linux 桥接（`br-external`）
4. **迁移 IP**：将物理网卡的 IP 迁移到桥接上
5. **禁用物理网卡 IP**：禁用物理网卡的 IP 配置

### 7.3 验证方法

```bash
# 查看策略状态
kubectl get nncp ubuntu-vm-external-bridge -o yaml

# 查看节点网络状态
kubectl get nodenetworkstate host1 -o jsonpath='{.status.currentState.interfaces[?(@.name=="br-external")]}'

# 在节点上查看
ip addr show br-external
ip addr show ens192
```

## 8. 总结

`reconcileBridgePolicy` 函数的核心功能是：

1. ✅ **自动检测**：从 NodeNetworkState 获取物理网卡的 IP 配置
2. ✅ **验证配置**：验证 IP 地址格式和配置完整性
3. ✅ **构建策略**：创建 NodeNetworkConfigurationPolicy 资源
4. ✅ **保持一致性**：确保桥接使用与物理网卡相同的 IP 配置方式
5. ✅ **声明式配置**：明确指定每个接口的状态，避免配置丢失

这样，NMState Operator 就可以根据策略自动在节点上创建桥接，并将物理网卡的 IP 迁移到桥接上，保证节点网络不中断。

