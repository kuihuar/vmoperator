# VM 网络规划：管理网络 + 外网访问

## 1. 需求分析

### 1.1 网络需求

- **管理网络**：用于 SSH、监控、管理操作
  - 通常需要固定 IP
  - 可能需要与物理网络隔离（VLAN）
  - 需要稳定可靠

- **外网网络**：用于访问互联网
  - 需要能够访问外网
  - 可能需要 NAT 或直接路由
  - 性能要求较高

### 1.2 网络拓扑

```
VM
├── 管理网络 (management)
│   ├── 接口：enp1s0 (或 eth0)
│   ├── IP：192.168.100.10/24 (示例)
│   └── 网关：192.168.100.1
│
└── 外网网络 (external)
    ├── 接口：enp2s0 (或 eth1)
    ├── IP：192.168.1.200/24 (示例)
    └── 网关：192.168.1.1
```

## 2. 方案对比

### 方案 1: 使用 macvlan（推荐，简单）

**特点：**
- 直接在物理网卡上创建虚拟接口
- 不需要预先配置桥接或 VLAN
- **不需要 NMState**
- 适合简单场景

**适用场景：**
- 物理网络已经配置好
- 不需要额外的网络隔离
- 快速部署

### 方案 2: 使用 bridge + NMState（灵活，复杂）

**特点：**
- 需要预先配置桥接
- **需要 NMState** 配置节点网络
- 支持 VLAN 隔离
- 更灵活的网络配置

**适用场景：**
- 需要网络隔离（VLAN）
- 需要动态配置桥接
- 复杂的网络拓扑

### 方案 3: 混合方案（推荐，平衡）

**特点：**
- 管理网络使用 bridge + VLAN（通过 NMState）
- 外网网络使用 macvlan（直接访问）
- 平衡了灵活性和简单性

## 3. 推荐方案：macvlan（双网卡）

### 3.1 为什么推荐 macvlan？

1. **简单**：不需要预先配置节点网络
2. **性能好**：直接使用物理网卡，延迟低
3. **不需要 NMState**：减少依赖和复杂性
4. **适合当前项目**：当前实现已经支持

### 3.2 网络配置示例

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
  namespace: default
spec:
  # ... 其他配置 ...
  
  networks:
    # 1. 管理网络（使用 Pod 网络，通过 Service 访问）
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp  # 或使用静态 IP
    
    # 2. 管理网络（Multus，固定 IP）
    - name: management
      type: macvlan
      bridgeName: ens160  # 物理网卡
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
        dnsServers:
          - 192.168.100.1
          - 114.114.114.114
    
    # 3. 外网网络（Multus，访问外网）
    - name: external
      type: macvlan
      bridgeName: ens160  # 或使用另一个物理网卡
      ipConfig:
        mode: static
        address: 192.168.1.200/24
        gateway: 192.168.1.1
        dnsServers:
          - 192.168.1.1
          - 114.114.114.114
          - 8.8.8.8
```

### 3.3 工作流程

```
1. Multus 创建 NAD（NetworkAttachmentDefinition）
   ├── management-nad: macvlan on ens160, IP 192.168.100.10/24
   └── external-nad: macvlan on ens160, IP 192.168.1.200/24

2. KubeVirt 创建 VM
   ├── default 网络：Pod 网络（用于集群内访问）
   ├── management 网络：Multus macvlan（管理网络）
   └── external 网络：Multus macvlan（外网网络）

3. Cloud-Init 配置网络
   ├── enp1s0: default 网络（DHCP）
   ├── enp2s0: management 网络（192.168.100.10/24）
   └── enp3s0: external 网络（192.168.1.200/24）
```

## 4. 高级方案：bridge + NMState（需要网络隔离）

### 4.1 何时需要这个方案？

- 需要 VLAN 隔离管理网络
- 需要动态配置桥接
- 需要更复杂的网络拓扑

### 4.2 网络配置示例

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
  namespace: default
spec:
  networks:
    # 1. 管理网络（bridge + VLAN）
    - name: management
      type: bridge
      bridgeName: br-mgmt  # 需要 NMState 预先创建
      vlanID: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
    
    # 2. 外网网络（macvlan，直接访问）
    - name: external
      type: macvlan
      bridgeName: ens160
      ipConfig:
        mode: static
        address: 192.168.1.200/24
        gateway: 192.168.1.1
```

### 4.3 NMState 配置（需要实现）

```yaml
# NodeNetworkConfigurationPolicy（由 NMState 管理）
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: management-bridge
spec:
  desiredState:
    interfaces:
      - name: br-mgmt
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens160.100  # VLAN 接口
      - name: ens160.100
        type: vlan
        state: up
        vlan:
          base-iface: ens160
          id: 100
```

## 5. 实际配置示例

### 5.1 完整配置（macvlan 方案）

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm-dual-network
  namespace: default
spec:
  cpu: 2
  memory: 4Gi
  osImage: "quay.io/kubevirt/fedora-cloud-container-disk-demo:latest"
  
  # 网络配置
  networks:
    # 默认网络（Pod 网络，用于集群内访问）
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
    
    # 管理网络（Multus macvlan）
    - name: management
      type: macvlan
      bridgeName: ens160  # 物理网卡名称
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
        dnsServers:
          - 192.168.100.1
          - 114.114.114.114
    
    # 外网网络（Multus macvlan）
    - name: external
      type: macvlan
      bridgeName: ens160  # 可以使用同一个物理网卡，或另一个网卡
      ipConfig:
        mode: static
        address: 192.168.1.200/24
        gateway: 192.168.1.1
        dnsServers:
          - 192.168.1.1
          - 114.114.114.114
          - 8.8.8.8
  
  # Cloud-Init 用户配置
  cloudInitUser:
    name: ubuntu
    passwordHash: "$1$7.t8q8zZ$59I1IiMXy5w3gIl5Yrn/4/"
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: "/bin/bash"
    groups:
      - sudo
      - adm
```

### 5.2 使用不同物理网卡（推荐）

如果节点有多个物理网卡，可以分别使用：

```yaml
networks:
  # 管理网络（使用 ens160）
  - name: management
    type: macvlan
    bridgeName: ens160
    ipConfig:
      mode: static
      address: 192.168.100.10/24
      gateway: 192.168.100.1
  
  # 外网网络（使用 ens161）
  - name: external
    type: macvlan
    bridgeName: ens161
    ipConfig:
      mode: static
      address: 192.168.1.200/24
      gateway: 192.168.1.1
```

## 6. 实施步骤

### 6.1 方案 1：macvlan（推荐）

**步骤：**

1. **确认物理网络**
   ```bash
   # 查看节点网卡
   ip addr show
   # 确认网卡名称（如 ens160）
   ```

2. **创建 Wukong CR**
   ```bash
   kubectl apply -f vm-dual-network.yaml
   ```

3. **验证网络**
   ```bash
   # 查看 VM 状态
   kubectl get vm ubuntu-vm-dual-network
   
   # 查看网络接口
   kubectl get vmi ubuntu-vm-dual-network-vm -o jsonpath='{.status.interfaces}'
   
   # 进入 VM 验证
   ssh ubuntu@192.168.100.10  # 管理网络
   ssh ubuntu@192.168.1.200    # 外网网络
   ```

**不需要的操作：**
- ❌ 不需要安装 NMState
- ❌ 不需要配置节点网络
- ❌ 不需要创建桥接

### 6.2 方案 2：bridge + NMState（高级）

**步骤：**

1. **安装 NMState Operator**
   ```bash
   helm repo add nmstate https://nmstate.github.io/nmstate-operator
   helm install nmstate nmstate/nmstate-operator \
     --namespace nmstate-system \
     --create-namespace
   ```

2. **创建 NodeNetworkConfigurationPolicy**
   ```bash
   kubectl apply -f nmstate-bridge-policy.yaml
   ```

3. **创建 Wukong CR**
   ```bash
   kubectl apply -f vm-dual-network-bridge.yaml
   ```

4. **验证网络**
   ```bash
   # 验证节点桥接
   ip addr show br-mgmt
   
   # 验证 VM 网络
   kubectl get vm ubuntu-vm-dual-network
   ```

## 7. 网络路由配置

### 7.1 VM 内部路由

Cloud-Init 会自动配置路由，但可以手动调整：

```yaml
# 在 Cloud-Init 中添加路由配置
network:
  version: 2
  ethernets:
    enp2s0:  # 管理网络
      addresses:
        - 192.168.100.10/24
      routes:
        - to: 192.168.100.0/24
          via: 192.168.100.1
          metric: 100
    
    enp3s0:  # 外网网络
      addresses:
        - 192.168.1.200/24
      routes:
        - to: 0.0.0.0/0
          via: 192.168.1.1
          metric: 200  # 较低优先级，优先使用管理网络
```

### 7.2 路由优先级

- **管理网络**：metric 100（高优先级）
- **外网网络**：metric 200（低优先级）

这样确保管理流量优先使用管理网络。

## 8. 安全考虑

### 8.1 网络隔离

- **管理网络**：可以配置防火墙规则，限制访问
- **外网网络**：可以配置 NAT，隐藏内部 IP

### 8.2 防火墙配置（可选）

```yaml
# 在 Cloud-Init 中配置防火墙
runcmd:
  - ufw allow from 192.168.100.0/24 to any port 22  # 只允许管理网络 SSH
  - ufw enable
```

## 9. 总结

### 9.1 推荐方案

| 场景 | 推荐方案 | 是否需要 NMState |
|------|---------|-----------------|
| **简单场景** | macvlan（双网卡） | ❌ 不需要 |
| **需要 VLAN 隔离** | bridge + NMState | ✅ 需要 |
| **高性能要求** | macvlan（不同物理网卡） | ❌ 不需要 |

### 9.2 实施建议

1. **优先使用 macvlan 方案**（简单、性能好）
2. **如果物理网络已配置好**，直接使用 macvlan
3. **如果需要 VLAN 隔离**，再考虑 bridge + NMState
4. **使用不同物理网卡**，避免网络冲突

### 9.3 当前项目支持

- ✅ **支持 macvlan**：已实现
- ✅ **支持多网络**：已实现
- ⚠️ **NMState**：当前为占位符，需要实现

## 10. 参考

- [Multus 网络配置流程图](./MULTUS_NETWORK_FLOW.md)
- [NMState 作用说明](./NMSTATE_EXPLANATION.md)
- [网络配置示例](../config/samples/vm_v1alpha1_wukong_rulai_multus.yaml)

