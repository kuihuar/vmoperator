# reconcileBridgePolicy 方法流程图

## 流程图

```mermaid
flowchart TD
    Start([开始: reconcileBridgePolicy]) --> GenPolicyName[生成策略名称<br/>policyName = wukong-name-network-name-bridge]
    
    GenPolicyName --> GetBridgeName{桥接名称<br/>BridgeName 是否为空?}
    GetBridgeName -->|为空| DefaultBridgeName[使用默认名称<br/>br-network-name]
    GetBridgeName -->|不为空| UseConfigBridgeName[使用配置的桥接名称]
    DefaultBridgeName --> CheckPhysicalInterface
    UseConfigBridgeName --> CheckPhysicalInterface
    
    CheckPhysicalInterface{物理接口<br/>PhysicalInterface<br/>是否为空?}
    CheckPhysicalInterface -->|为空| Error1[返回错误:<br/>physicalInterface is required]
    CheckPhysicalInterface -->|不为空| CheckVLAN
    
    CheckVLAN{VLANID<br/>是否配置?}
    CheckVLAN -->|已配置| Error2[返回错误:<br/>VLAN not supported yet]
    CheckVLAN -->|未配置| CheckPolicyExists
    
    CheckPolicyExists[检查 NodeNetworkConfigurationPolicy<br/>是否存在]
    CheckPolicyExists --> GetBridgeIP[获取桥接的 IP 配置<br/>从 NodeNetworkState 查找桥接]
    
    GetBridgeIP --> BridgeExists{桥接是否存在<br/>在 NodeNetworkState 中?}
    BridgeExists -->|不存在<br/>首次创建| UseDHCP[使用 DHCP<br/>ipInfo.useDHCP = true]
    BridgeExists -->|存在| GetBridgeIPConfig[获取桥接的 IP 配置<br/>ipAddress + useDHCP]
    
    UseDHCP --> ValidateIP
    GetBridgeIPConfig --> ValidateIP
    
    ValidateIP{IP 配置验证}
    ValidateIP -->|静态 IP 且地址为空| FallbackDHCP[回退到 DHCP<br/>useDHCP = true]
    ValidateIP -->|静态 IP 且格式错误| Error3[返回错误:<br/>invalid IP address format]
    ValidateIP -->|DHCP 或静态 IP 有效| BuildDesiredState
    
    FallbackDHCP --> BuildDesiredState
    
    BuildDesiredState[构建 desiredState<br/>调用 buildBridgeDesiredState]
    BuildDesiredState --> BuildError{构建失败?}
    BuildError -->|失败| Error4[返回错误:<br/>failed to build desiredState]
    BuildError -->|成功| PolicyCheck{策略是否存在?}
    
    PolicyCheck -->|存在| UpdatePolicy[更新策略<br/>使用 existingNNCP<br/>设置 spec.desiredState<br/>调用 Update]
    PolicyCheck -->|不存在| CreatePolicy[创建策略<br/>新建 Unstructured<br/>设置 GVK + Name<br/>设置 spec.desiredState<br/>调用 Create]
    
    UpdatePolicy --> UpdateError{更新失败?}
    CreatePolicy --> CreateError{创建失败?}
    
    UpdateError -->|失败| Error5[返回错误:<br/>failed to update policy]
    UpdateError -->|成功| Success([成功返回])
    
    CreateError -->|失败| Error6[返回错误:<br/>failed to create policy]
    CreateError -->|成功| Success
    
    Error1 --> End([结束])
    Error2 --> End
    Error3 --> End
    Error4 --> End
    Error5 --> End
    Error6 --> End
    Success --> End
    
    style Start fill:#90EE90
    style Success fill:#90EE90
    style Error1 fill:#FFB6C1
    style Error2 fill:#FFB6C1
    style Error3 fill:#FFB6C1
    style Error4 fill:#FFB6C1
    style Error5 fill:#FFB6C1
    style Error6 fill:#FFB6C1
    style End fill:#D3D3D3
```

## buildBridgeDesiredState 子流程

```mermaid
flowchart TD
    Start([开始: buildBridgeDesiredState]) --> BuildBridgeInterface[构建桥接接口配置<br/>name: bridgeName<br/>type: linux-bridge<br/>state: up<br/>bridge.port: physicalInterface<br/>bridge.options.stp: false]
    
    BuildBridgeInterface --> CheckIPMode{IP 模式?}
    CheckIPMode -->|DHCP| ConfigDHCP[配置桥接 IPv4<br/>enabled: true<br/>dhcp: true]
    CheckIPMode -->|静态 IP| ParseIP[解析 IP 地址<br/>格式: 192.168.1.100/24]
    
    ParseIP --> ParseError{解析失败?}
    ParseError -->|失败| Error[返回错误:<br/>failed to parse IP]
    ParseError -->|成功| ConfigStaticIP[配置桥接 IPv4<br/>enabled: true<br/>dhcp: false<br/>address: ip/prefix-length]
    
    ConfigDHCP --> AddBridgeInterface
    ConfigStaticIP --> AddBridgeInterface
    
    AddBridgeInterface[将桥接接口添加到 interfaces 列表]
    AddBridgeInterface --> BuildPhysicalInterface[构建物理接口配置<br/>name: physicalInterface<br/>type: ethernet<br/>state: up<br/>ipv4.enabled: false]
    
    BuildPhysicalInterface --> AddPhysicalInterface[将物理接口添加到 interfaces 列表]
    AddPhysicalInterface --> Return[返回 desiredState<br/>interfaces: [...]]
    
    Return --> End([结束])
    Error --> End
    
    style Start fill:#90EE90
    style Return fill:#90EE90
    style Error fill:#FFB6C1
    style End fill:#D3D3D3
```

## 关键点说明

### 1. IP 配置获取逻辑
- **桥接已存在**：从 NodeNetworkState 获取桥接的 IP 配置
- **桥接不存在**（首次创建）：使用 DHCP
- **注意**：物理接口没有 IP（`ipv4.enabled: false`），IP 在桥接上

### 2. 错误处理
- 物理接口为空 → 返回错误
- VLAN 已配置 → 返回错误（暂不支持）
- IP 地址格式错误 → 返回错误
- 策略创建/更新失败 → 返回错误

### 3. desiredState 结构
```yaml
interfaces:
  # 桥接接口
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
      dhcp: true  # 或静态 IP 配置
  
  # 物理接口（禁用 IP）
  - name: ens192
    type: ethernet
    state: up
    ipv4:
      enabled: false
```

### 4. 策略名称规则
- 格式：`{wukong-name}-{network-name}-bridge`
- 示例：`my-vm-external-bridge`

### 5. 桥接名称规则
- 如果配置了 `BridgeName`：使用配置的值
- 如果未配置：使用默认格式 `br-{network-name}`
- 示例：`br-external`

