# 如何获取物理网卡信息

## 当前实现：从 NodeNetworkState 获取

当前代码逻辑中，物理网卡信息是**从 NodeNetworkState 资源中获取的**。

## 获取流程

### 1. 调用位置

在 `pkg/network/nmstate.go` 的 `reconcileBridgePolicy` 函数中：

```go
// 自动获取物理网卡的 IP 配置信息（IP 地址和配置方式：DHCP 或静态）
var nodeIP string
var useDHCP bool
ipInfo, err := getIPConfigFromNodeNetworkState(ctx, c, physicalInterface)
```

### 2. 获取函数：`getIPConfigFromNodeNetworkState`

```go
func getIPConfigFromNodeNetworkState(ctx context.Context, c client.Client, interfaceName string) (*ipConfigInfo, error) {
    // 1. 列出所有 NodeNetworkState 资源
    nodeNetworkStateList := &unstructured.UnstructuredList{}
    nodeNetworkStateList.SetGroupVersionKind(schema.GroupVersionKind{
        Group:   "nmstate.io",
        Version: "v1beta1",
        Kind:    "NodeNetworkStateList",
    })
    err := c.List(ctx, nodeNetworkStateList)
    
    // 2. 遍历所有节点的 NodeNetworkState
    for _, item := range nodeNetworkStateList.Items {
        // 3. 获取接口列表
        interfaces, found, err := unstructured.NestedSlice(item.Object, "status", "currentState", "interfaces")
        
        // 4. 遍历接口，查找目标接口（如 ens192）
        for _, iface := range interfaces {
            name, _ := ifaceMap["name"].(string)
            if name != interfaceName {
                continue  // 不是目标接口，跳过
            }
            
            // 5. 找到目标接口，提取 IP 配置信息
            // - 检查是否使用 DHCP（ipv4.dhcp）
            // - 获取 IP 地址（ipv4.address[0].ip 和 prefix-length）
        }
    }
}
```

### 3. 数据路径

```
Kubernetes API Server
    ↓
NodeNetworkState 资源（如 host1）
    ↓
status.currentState.interfaces[]
    ↓
找到 name == "ens192" 的接口
    ↓
提取 ipv4.dhcp 和 ipv4.address[0]
    ↓
返回 ipConfigInfo{ipAddress, useDHCP}
```

## 为什么从 NodeNetworkState 获取？

### 优点

1. ✅ **统一的数据源**：NodeNetworkState 是节点网络状态的权威来源
2. ✅ **包含完整信息**：不仅有 IP 地址，还有 DHCP/静态配置方式
3. ✅ **Kubernetes 原生**：通过 Kubernetes API 访问，无需 SSH 到节点
4. ✅ **自动更新**：NodeNetworkState 会随网络变化自动更新

### 其他可选方案（未采用）

1. **直接 SSH 到节点**：
   - 需要 SSH 配置和凭证管理
   - 跨节点访问复杂
   - 不推荐

2. **通过 Node 资源**：
   - Node 资源不包含详细的网络接口信息
   - 只有基本的节点状态信息

3. **通过 DaemonSet 代理**：
   - 需要额外的组件
   - 增加复杂性

## 代码示例

### 实际的数据提取

```go
// 从 NodeNetworkState 中提取 ens192 的信息
interfaces := nodeNetworkState.status.currentState.interfaces

// 找到 ens192
for _, iface := range interfaces {
    if iface.name == "ens192" {
        // 检查 DHCP
        useDHCP := iface.ipv4.dhcp  // true
        
        // 获取 IP 地址
        ipAddress := iface.ipv4.address[0].ip + "/" + iface.ipv4.address[0].prefix-length
        // "192.168.0.105/24"
        
        return &ipConfigInfo{
            ipAddress: ipAddress,
            useDHCP:   useDHCP,
        }
    }
}
```

## 总结

**当前代码就是从 NodeNetworkState 资源中获取物理网卡信息的**。

- **数据源**：`NodeNetworkState.status.currentState.interfaces[]`
- **查找方式**：遍历所有 NodeNetworkState，找到匹配的接口名称
- **提取信息**：IP 地址、DHCP/静态配置方式

这种方式的优势是：
- 利用 NMState Operator 已经收集和维护的网络状态信息
- 无需额外的网络访问或权限
- 自动跟随网络状态变化

