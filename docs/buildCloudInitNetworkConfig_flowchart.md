# buildCloudInitNetworkConfig 流程图

## 概述

`buildCloudInitNetworkConfig` 函数用于构建 Cloud-Init 网络配置（Netplan 格式），**仅支持 DHCP 模式**。该函数遍历 VM 的网络配置，为每个符合条件（DHCP 模式的 Multus 网络）的网络生成 Cloud-Init 网络配置，最终生成 Netplan 格式的 YAML 字符串。

## 流程图

```mermaid
flowchart TD
    Start([开始: buildCloudInitNetworkConfig]) --> Init[初始化]
    
    Init --> CreateMap[创建 netStatusMap<br/>映射网络名称到 NetworkStatus]
    CreateMap --> InitVars[初始化变量<br/>networkConfig: strings.Builder<br/>headerWritten: false<br/>multusInterfaceIndex: 1]
    
    InitVars --> LoopStart{遍历 vmp.Spec.Networks}
    
    LoopStart -->|有更多网络| CheckDefault{网络名称 == 'default'?}
    CheckDefault -->|是| SkipDefault[跳过<br/>continue]
    SkipDefault --> LoopStart
    
    CheckDefault -->|否| CheckIPConfig{IPConfig == nil?}
    CheckIPConfig -->|是| SkipNoIPConfig[跳过<br/>continue]
    SkipNoIPConfig --> LoopStart
    
    CheckIPConfig -->|否| CheckMode{IPConfig.Mode == 'dhcp'?}
    CheckMode -->|否| SkipNotDHCP[跳过<br/>continue]
    SkipNotDHCP --> LoopStart
    
    CheckMode -->|是| CheckNAD[从 netStatusMap 获取 netStatus]
    CheckNAD --> CheckNADName{有 netStatus 且<br/>NADName == ''?}
    CheckNADName -->|是| SkipNoNAD[跳过<br/>不是 Multus 网络<br/>continue]
    SkipNoNAD --> LoopStart
    
    CheckNADName -->|否| CheckHeader{headerWritten == false?}
    CheckHeader -->|是| WriteHeader[写入 Netplan 头部<br/>network:<br/>  version: 2<br/>  ethernets:<br/>headerWritten = true]
    CheckHeader -->|否| GetMAC[获取 MAC 地址和接口名称]
    WriteHeader --> GetMAC
    
    GetMAC --> GetFromStatus{从 NetworkStatus<br/>获取 MAC 和接口名}
    GetFromStatus --> CheckMACEmpty{MAC 地址为空?}
    
    CheckMACEmpty -->|否| SetInterfaceName[确定接口标识符<br/>优先使用 netStatus.Interface<br/>否则使用 eth{multusInterfaceIndex}]
    CheckMACEmpty -->|是| TryVMI[尝试从 VMI 获取 MAC<br/>查询 VMI Status.Interfaces]
    TryVMI --> SetInterfaceName
    
    SetInterfaceName --> WriteInterface[写入接口配置<br/>interfaceName:]
    WriteInterface --> CheckMAC{macAddress != ''?}
    
    CheckMAC -->|是| WriteMAC[写入 MAC 匹配配置<br/>match:<br/>  macaddress: xxx<br/>set-name: interfaceName]
    CheckMAC -->|否| LogWarning[记录警告日志<br/>使用索引匹配]
    
    WriteMAC --> WriteDHCP[写入 DHCP 配置<br/>dhcp4: true<br/>dhcp6: false]
    LogWarning --> WriteDHCP
    
    WriteDHCP --> IncrementIndex[multusInterfaceIndex++]
    IncrementIndex --> LoopStart
    
    LoopStart -->|没有更多网络| Return[返回 networkConfig.String]
    Return --> End([结束])
    
    style Start fill:#90EE90
    style End fill:#FFB6C1
    style CheckDefault fill:#FFE4B5
    style CheckIPConfig fill:#FFE4B5
    style CheckMode fill:#FFE4B5
    style CheckNADName fill:#FFE4B5
    style CheckHeader fill:#FFE4B5
    style CheckMAC fill:#FFE4B5
    style WriteHeader fill:#87CEEB
    style WriteDHCP fill:#87CEEB
    style SkipDefault fill:#D3D3D3
    style SkipNoIPConfig fill:#D3D3D3
    style SkipNotDHCP fill:#D3D3D3
    style SkipNoNAD fill:#D3D3D3
```

## 详细说明

### 1. 初始化阶段

- **创建映射表**：将 `networks` 列表转换为 `netStatusMap`，便于后续查找
- **初始化变量**：
  - `networkConfig`: `strings.Builder`，用于构建 Netplan 配置字符串
  - `headerWritten`: `false`，用于确保 `network:` 头部只写入一次
  - `multusInterfaceIndex`: `1`，用于跟踪 Multus 接口的索引（从 1 开始，因为 0 是 default）

### 2. 网络过滤条件

函数只处理满足以下所有条件的网络：

1. **不是 default 网络**：default 网络使用 Pod 网络，不需要 Cloud-Init 配置
2. **有 IPConfig**：`net.IPConfig != nil`
3. **模式为 DHCP**：`net.IPConfig.Mode == "dhcp"`
4. **是 Multus 网络**：必须有 `NADName`（通过 `netStatusMap` 检查）

### 3. Netplan 头部写入

- **第一次遇到符合条件的网络时**，写入 Netplan 格式的头部：
  ```yaml
  network:
    version: 2
    ethernets:
  ```
- 使用 `headerWritten` 标志确保头部只写入一次

### 4. MAC 地址和接口名称获取

按以下优先级获取 MAC 地址和接口名称：

1. **优先使用 NetworkStatus**：
   - `netStatus.MACAddress`
   - `netStatus.Interface`

2. **如果 MAC 地址为空，尝试从 VMI 获取**：
   - 查询 `VirtualMachineInstance`（如果存在）
   - 从 `vmi.Status.Interfaces` 中查找匹配的网络名称
   - 获取 `iface.MAC`

3. **确定接口标识符**：
   - 如果 `netStatus.Interface` 存在，使用它
   - 否则使用 `fmt.Sprintf("eth%d", multusInterfaceIndex)`

### 5. Netplan 配置生成

对于每个符合条件的网络，生成以下配置：

**如果 MAC 地址存在**：
```yaml
    eth1:
      match:
        macaddress: fa:8b:64:25:1f:0c
      set-name: eth1
      dhcp4: true
      dhcp6: false
```

**如果 MAC 地址不存在**：
```yaml
    eth1:
      dhcp4: true
      dhcp6: false
```
（会记录警告日志，依赖 KubeVirt 默认的接口顺序）

### 6. 索引递增

处理完每个网络后，`multusInterfaceIndex++`，用于下一个网络的接口标识符。

## 代码示例

### 输入示例

```yaml
spec:
  networks:
    - name: default  # 会被跳过
      type: pod
    - name: external
      type: bridge
      ipConfig:
        mode: dhcp  # 会被处理
```

### 输出示例

```yaml
network:
  version: 2
  ethernets:
    eth1:
      match:
        macaddress: fa:8b:64:25:1f:0c
      set-name: eth1
      dhcp4: true
      dhcp6: false
```

## 关键设计点

1. **仅支持 DHCP**：当前实现只处理 `IPConfig.Mode == "dhcp"` 的网络，静态 IP 配置已被移除
2. **头部只写一次**：使用 `headerWritten` 标志确保 Netplan 头部只写入一次
3. **MAC 地址匹配**：优先使用 MAC 地址匹配，这是 Netplan 中最可靠的接口匹配方式
4. **Multus 网络限制**：只处理有 `NADName` 的 Multus 网络，跳过 Pod 网络
5. **索引跟踪**：使用 `multusInterfaceIndex` 为接口生成默认名称（`eth1`, `eth2`, ...）

## 参考

- 函数位置：`pkg/kubevirt/vm.go:buildCloudInitNetworkConfig`
- Netplan 文档：https://netplan.io/reference/
- Cloud-Init 网络配置：https://cloudinit.readthedocs.io/en/latest/topics/network-config.html

