# 使用 ens192 桥接网络配置指南

## 概述

本指南说明如何配置 Wukong VM 使用 `ens192` (192.168.0.121/24) 网卡桥接访问外网。

## 前置条件

1. ✅ 节点已有 `ens192` 网卡，IP 为 `192.168.0.121/24`
2. ✅ 网关为 `192.168.0.1`
3. ✅ NMState Operator 已安装并运行
4. ✅ Multus CNI 已安装

## 网络配置

### 当前节点网络状态

```bash
# 检查 ens192 配置
ip addr show ens192

# 输出示例：
# 42: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP
#     inet 192.168.0.121/24 brd 192.168.0.255 scope global noprefixroute ens192
```

### 网关配置

```bash
# 检查默认路由
ip route show default

# 输出示例：
# default via 192.168.0.1 dev ens192 proto static metric 101
```

## Wukong 配置示例

### 完整配置示例

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm-external-network
spec:
  cpu: 2
  memory: 4Gi
  
  disks:
    - name: system
      size: 5Gi
      storageClassName: longhorn
      boot: true
      image: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"
    
    - name: data
      size: 10Gi
      storageClassName: longhorn
      boot: false
  
  networks:
    # 1. 默认网络（Pod 网络，用于集群内访问）
    - name: default
    
    # 2. 外网网络（Bridge + NMState，使用 ens192 桥接）
    - name: external
      type: bridge
      bridgeName: "br-external"      # 桥接名称
      physicalInterface: "ens192"     # 物理网卡名称，NMState 会将此网卡作为桥接端口
      ipConfig:
        mode: static
        address: "192.168.0.200/24"  # VM 的 IP 地址（确保在 192.168.0.0/24 网段且未被占用）
        gateway: "192.168.0.1"       # 网关地址
        dnsServers:
          - "192.168.0.1"            # 网关 DNS
          - "114.114.114.114"        # 备用 DNS
          - "8.8.8.8"               # Google DNS
  
  cloudInitUser:
    name: ubuntu
    passwordHash: "$1$7.t8q8zZ$59I1IiMXy5w3gIl5Yrn/4/"  # ubuntu123
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: "/bin/bash"
    groups:
      - sudo
      - adm
      - dialout
    lockPasswd: false
  
  startStrategy:
    autoStart: true
```

## 工作原理

### 1. NMState 创建桥接

当创建 Wukong 资源时，VM Operator 会：

1. **创建 NodeNetworkConfigurationPolicy**：
   - 桥接名称：`br-external`
   - 物理网卡：`ens192`（作为桥接端口）
   - NMState 会自动将 `ens192` 的 IP 地址迁移到桥接上

2. **桥接配置**：
   ```yaml
   apiVersion: nmstate.io/v1
   kind: NodeNetworkConfigurationPolicy
   metadata:
     name: ubuntu-vm-external-network-external-bridge
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
   ```

### 2. Multus 创建 NAD

VM Operator 会创建 NetworkAttachmentDefinition：

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ubuntu-vm-external-network-external
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-external",
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.0.0/24",
        "rangeStart": "192.168.0.200",
        "rangeEnd": "192.168.0.200"
      }
    }
```

### 3. VM 网络配置

VM 启动后，Cloud-Init 会配置网络：

```yaml
network:
  version: 2
  ethernets:
    eth1:  # 或实际接口名称
      match:
        macaddress: <MAC地址>
      addresses:
        - 192.168.0.200/24
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
          - 114.114.114.114
          - 8.8.8.8
```

## 重要注意事项

### ⚠️ IP 地址迁移

当 NMState 创建桥接并将 `ens192` 作为端口时：

1. **节点 IP 地址迁移**：
   - `ens192` 的 IP (`192.168.0.121`) 会被迁移到桥接 `br-external` 上
   - 节点仍然可以通过 `br-external` 访问网络
   - 这是 NMState 的自动行为，确保节点网络不中断

2. **验证迁移**：
   ```bash
   # 创建 Wukong 后，检查桥接 IP
   ip addr show br-external
   
   # 应该看到 192.168.0.121/24 在 br-external 上
   ```

### ⚠️ IP 地址规划

1. **VM IP 地址选择**：
   - 确保 VM IP (`192.168.0.200`) 在 `192.168.0.0/24` 网段
   - 确保 IP 未被其他设备使用
   - 确保 IP 不在 DHCP 范围内

2. **检查 IP 冲突**：
   ```bash
   # 检查 IP 是否被占用
   ping 192.168.0.200
   
   # 检查 DHCP 范围（如果可能）
   # 确保选择的 IP 不在 DHCP 范围内
   ```

### ⚠️ 网关配置

- 网关必须是 `192.168.0.1`（根据实际网络环境调整）
- 确保网关可达：
  ```bash
  ping 192.168.0.1
  ```

## 部署步骤

### 1. 检查前置条件

```bash
# 检查 ens192 配置
ip addr show ens192

# 检查网关
ip route show default

# 检查 NMState Operator
kubectl get pods -n nmstate

# 检查 Multus
kubectl get pods -A | grep multus
```

### 2. 创建 Wukong 资源

```bash
# 使用示例配置创建 VM
kubectl apply -f config/samples/vm_v1alpha1_wukong_dual_network.yaml

# 或使用自定义配置
kubectl apply -f your-wukong-config.yaml
```

### 3. 验证网络配置

```bash
# 检查 NMState 策略
kubectl get nodenetworkconfigurationpolicy

# 检查桥接创建
ip addr show br-external

# 检查 NAD 创建
kubectl get networkattachmentdefinition

# 检查 VM 状态
kubectl get wukong ubuntu-vm-external-network
kubectl get vm ubuntu-vm-external-network-vm
```

### 4. 验证 VM 网络

```bash
# 进入 VM（如果已启动）
virtctl console ubuntu-vm-external-network-vm

# 在 VM 内检查网络
ip addr show
ip route show
ping 192.168.0.1
ping 8.8.8.8
```

## 故障排查

### 问题 1: 桥接未创建

**症状**：`br-external` 不存在

**检查**：
```bash
# 检查 NMState 策略状态
kubectl get nodenetworkconfigurationpolicy -o yaml

# 检查 NMState 日志
kubectl logs -n nmstate -l app=nmstate-handler
```

**解决**：
- 确保 NMState Operator 正常运行
- 检查策略配置是否正确
- 检查节点网络配置是否有冲突

### 问题 2: VM 无法访问外网

**症状**：VM 可以 ping 通网关，但无法访问外网

**检查**：
```bash
# 在 VM 内检查路由
ip route show

# 检查 DNS
nslookup google.com

# 检查防火墙规则（在节点上）
iptables -L -n
```

**解决**：
- 检查节点防火墙规则
- 检查网关配置
- 检查 DNS 配置

### 问题 3: 节点失去网络连接

**症状**：创建桥接后，节点无法访问网络

**原因**：`ens192` 的 IP 未正确迁移到桥接

**解决**：
```bash
# 检查桥接 IP
ip addr show br-external

# 如果桥接没有 IP，手动添加
sudo ip addr add 192.168.0.121/24 dev br-external

# 或删除 NMState 策略，重新配置
kubectl delete nodenetworkconfigurationpolicy <policy-name>
```

## 相关文档

- [NMState 安装指南](./NMSTATE_INSTALLATION.md)
- [VM IP 地址规划](./VM_IP_ADDRESS_PLANNING.md)
- [桥接 Netplan 配置](./BRIDGE_NETPLAN_CONFIG.md)

