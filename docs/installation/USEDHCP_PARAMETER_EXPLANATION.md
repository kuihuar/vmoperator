# useDHCP 参数说明

## 1. useDHCP 是什么？

`useDHCP` **不是 YAML 文件中的参数**，而是 **Go 代码中的一个变量**，用于标识物理网卡是否使用 DHCP 来获取 IP 地址。

## 2. useDHCP 的定义

### 2.1 数据结构定义

```go
// ipConfigInfo 存储从 NodeNetworkState 获取的 IP 配置信息
type ipConfigInfo struct {
	ipAddress string // IP 地址，格式: "192.168.0.105/24"
	useDHCP   bool   // 是否使用 DHCP
}
```

### 2.2 变量使用

```go
// 从 NodeNetworkState 获取 IP 配置信息
ipInfo, err := getIPConfigFromNodeNetworkState(ctx, c, physicalInterface)

// 提取 useDHCP 字段
useDHCP := ipInfo.useDHCP
```

## 3. useDHCP 的来源

`useDHCP` 是从 **NodeNetworkState 资源**中自动检测的，不是从用户的 YAML 配置文件中读取的。

### 3.1 检测逻辑

```go
func getIPConfigFromNodeNetworkState(ctx context.Context, c client.Client, interfaceName string) (*ipConfigInfo, error) {
    // ... 获取 NodeNetworkState 资源 ...
    
    // 检查是否启用 DHCP
    dhcp, found, _ := unstructured.NestedBool(ipv4, "dhcp")
    useDHCP := found && dhcp
    
    // 返回结果
    return &ipConfigInfo{
        ipAddress: ipAddress,
        useDHCP:   useDHCP,
    }
}
```

### 3.2 数据来源路径

```
NodeNetworkState 资源（Kubernetes）
    ↓
status.currentState.interfaces[]
    ↓
找到 name == "ens192" 的接口
    ↓
提取 ipv4.dhcp 字段
    ↓
useDHCP = true/false
```

### 3.3 实际数据示例

在 NodeNetworkState 中，物理网卡的配置可能是这样的：

```json
{
  "name": "ens192",
  "type": "ethernet",
  "ipv4": {
    "dhcp": true,              // ← 这里决定 useDHCP 的值
    "enabled": true,
    "address": [
      {
        "ip": "192.168.0.105",
        "prefix-length": 24
      }
    ]
  }
}
```

如果 `ipv4.dhcp` 为 `true`，则 `useDHCP = true`（使用 DHCP）
如果 `ipv4.dhcp` 为 `false` 或不存在，则 `useDHCP = false`（使用静态 IP）

## 4. useDHCP 的作用

### 4.1 决定桥接的 IP 配置方式

```go
if useDHCP {
    // 物理网卡使用 DHCP，桥接也使用 DHCP
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "dhcp":    true,
    }
} else {
    // 物理网卡使用静态 IP，桥接也使用静态 IP
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "dhcp":    false,
        "address": []interface{}{
            map[string]interface{}{
                "ip":            ip,
                "prefix-length": int64(prefixLen),
            },
        },
    }
}
```

### 4.2 确保配置一致性

**关键原则**：桥接必须使用与物理网卡相同的 IP 配置方式（DHCP 或静态 IP），才能保证节点网络不中断。

- 如果物理网卡是 DHCP → 桥接也配置为 DHCP
- 如果物理网卡是静态 IP → 桥接也配置为相同的静态 IP

## 5. 为什么不在 YAML 文件中？

### 5.1 自动检测的优势

1. **无需用户配置**：用户不需要手动指定物理网卡是 DHCP 还是静态 IP
2. **自动适应变化**：如果物理网卡从静态 IP 改为 DHCP（或反之），代码会自动适应
3. **减少配置错误**：避免用户配置与实际网络状态不一致

### 5.2 数据来源

- **不是从用户的 Wukong YAML 配置中读取**
- **不是从 NodeNetworkConfigurationPolicy YAML 中读取**
- **是从 NodeNetworkState 资源中自动检测的**

## 6. 如何查看 useDHCP 的值？

### 6.1 查看 NodeNetworkState

```bash
# 查看物理网卡是否使用 DHCP
kubectl get nodenetworkstate host1 -o jsonpath='{.status.currentState.interfaces[?(@.name=="ens192")].ipv4.dhcp}'
```

**输出**：
- `true`：使用 DHCP
- `false`：使用静态 IP
- 空：没有配置或接口不存在

### 6.2 查看日志

代码中会记录日志：

```go
logger.Info("Auto-detected IP config from NodeNetworkState", 
    "ipAddress", ipInfo.ipAddress, 
    "useDHCP", ipInfo.useDHCP, 
    "interface", physicalInterface)
```

**日志示例**：
```
Auto-detected IP config from NodeNetworkState ipAddress=192.168.0.105/24 useDHCP=true interface=ens192
```

## 7. 总结

| 项目 | 说明 |
|------|------|
| **类型** | Go 代码中的变量（bool 类型） |
| **来源** | 从 NodeNetworkState 资源自动检测 |
| **位置** | `pkg/network/nmstate.go` |
| **作用** | 标识物理网卡是否使用 DHCP |
| **YAML 文件** | ❌ 不在任何 YAML 文件中 |
| **用户配置** | ❌ 用户不需要配置，自动检测 |

**关键点**：
- `useDHCP` 是代码内部使用的变量，不是用户配置参数
- 它从 NodeNetworkState 自动检测，确保桥接配置与物理网卡一致
- 用户无需关心这个参数，系统会自动处理

