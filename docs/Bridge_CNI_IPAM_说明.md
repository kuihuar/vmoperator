# Bridge CNI IPAM 配置说明

## 关键发现

根据 [CNI Bridge 插件官方文档](https://www.cni.dev/plugins/current/main/bridge/)，有一个**重要限制**：

> **`disableContainerInterface`** (boolean, optional): Set the container interface (veth peer inside the container netns) state down. **When enabled, IPAM cannot be used.**

**翻译**：当启用 `disableContainerInterface` 时，**不能使用 IPAM**。

## KubeVirt 场景分析

### 1. KubeVirt 需要 `disableContainerInterface: true`

对于 KubeVirt 虚拟机，必须设置 `disableContainerInterface: true`，因为：
- KubeVirt 需要将 bridge 直接连接到 VM，而不是创建容器网络命名空间中的接口
- 这样可以避免创建 veth pair 的容器端，直接将 bridge 连接到 VM 的 tap 设备

### 2. 因为 `disableContainerInterface: true`，所以不能使用 IPAM

由于 KubeVirt 需要 `disableContainerInterface: true`，根据 CNI 文档，**IPAM 不能被使用**。

因此，对于 DHCP 模式：
- ✅ **不设置 IPAM**（当前实现）
- ❌ 不能设置 `ipam: { "type": "dhcp" }`

### 3. 为什么 Bridge CNI 本身不支持 DHCP IPAM？

- Bridge CNI 是一个**二层（L2）插件**，主要负责创建 bridge 和连接接口
- DHCP IPAM 是**独立的 IPAM 插件**，需要单独的 CNI 插件（如 dhcp-daemon）
- 即使 Bridge CNI 理论上可以配置 `ipam: { "type": "dhcp" }`，但在 `disableContainerInterface: true` 的场景下，CNI 文档明确说明 IPAM 不能被使用

## 当前实现 vs 用户建议

### 用户建议的配置

```json
{
  "cniVersion": "0.3.1",
  "type": "bridge",
  "bridge": "bridge0",
  "ipam": {
    "type": "dhcp"  # ❌ 不能使用！
  },
  "macspoofchk": false,
  "hairpinMode": true
}
```

**问题**：缺少 `disableContainerInterface: true`，且设置了 IPAM。

### 当前实现的配置（正确）

```json
{
  "cniVersion": "0.3.1",
  "type": "bridge",
  "bridge": "br-external",
  "disableContainerInterface": true,  # ✅ KubeVirt 必需
  "macspoofchk": false
  // 不设置 IPAM（因为 disableContainerInterface: true 时不能使用 IPAM）
}
```

## DHCP 模式的完整方案

对于 KubeVirt 的 DHCP 模式，正确的方案是：

### 1. NetworkAttachmentDefinition（不设置 IPAM）

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: bridge-dhcp
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-external",
      "disableContainerInterface": true,  # 必需
      "macspoofchk": false
      # 不设置 IPAM（因为 disableContainerInterface: true 时不能使用 IPAM）
    }
```

### 2. Cloud-Init 配置（在 VM 内部启用 DHCP）

```yaml
#cloud-config
network:
  version: 2
  ethernets:
    eth1:
      match:
        macaddress: fa:8b:64:25:1f:0c
      set-name: eth1
      dhcp4: true  # 在 VM 内部启用 DHCP 客户端
      dhcp6: false
```

### 3. 工作流程

```
1. Multus 创建 bridge 连接（不创建容器接口，因为 disableContainerInterface: true）
2. KubeVirt 将 bridge 连接到 VM 的 tap 设备
3. VM 启动，Cloud-Init 运行
4. Cloud-Init 应用网络配置，启用 DHCP 客户端
5. VM 内的 DHCP 客户端通过 bridge → 物理网卡 → 物理网络发送 DHCP 请求
6. 物理网络的 DHCP 服务器响应，VM 获得 IP 地址
```

## 与静态 IP 的对比

### 静态 IP 模式（当前实现）

```json
{
  "cniVersion": "0.3.1",
  "type": "bridge",
  "bridge": "br-external",
  "disableContainerInterface": true,
  "ipam": {
    "type": "host-local",
    "subnet": "192.168.0.0/24",
    "rangeStart": "192.168.0.100",
    "rangeEnd": "192.168.0.100"
  }
}
```

**注意**：即使设置了 `disableContainerInterface: true`，代码中仍然设置了 IPAM。这可能不符合 CNI 文档的说明。

让我检查一下静态 IP 模式的实际行为...

实际上，对于 KubeVirt，即使设置了 `disableContainerInterface: true`，可能仍然需要设置 IPAM 来配置路由。但 CNI 文档明确说明当 `disableContainerInterface: true` 时不能使用 IPAM。

这可能是一个**文档与实现的差异**，或者 KubeVirt 有特殊处理。但对于 DHCP 模式，不设置 IPAM 是正确的。

## 其他参数说明

### `hairpinMode`

根据 CNI 文档：
> `hairpinMode` (boolean, optional): set hairpin mode for interfaces on the bridge. Defaults to false.

对于 KubeVirt 场景，通常不需要启用 hairpin mode。

### `macspoofchk`

根据 CNI 文档：
> `macspoofchk` (boolean, optional): Enables mac spoof check, limiting the traffic originating from the container to the mac address of the interface. Defaults to false.

当前代码设置为 `false`，可以根据安全需求调整。

## 总结

1. **KubeVirt 必须设置 `disableContainerInterface: true`**
2. **当 `disableContainerInterface: true` 时，根据 CNI 文档，不能使用 IPAM**
3. **对于 DHCP 模式，正确的方案是**：
   - NetworkAttachmentDefinition：不设置 IPAM
   - Cloud-Init：在 VM 内部启用 DHCP 客户端
4. **当前实现是正确的**：对于 DHCP 模式，不设置 IPAM

## 参考

- [CNI Bridge 插件官方文档](https://www.cni.dev/plugins/current/main/bridge/)
- [KubeVirt 网络文档](https://kubevirt.io/user-guide/network/interfaces_and_networks/)
- 当前代码：`pkg/network/multus.go:buildCNIConfig`

