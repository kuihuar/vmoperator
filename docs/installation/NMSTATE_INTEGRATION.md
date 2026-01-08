# NMState 集成说明

## 1. 功能概述

NMState 集成已实现，可以根据 NetworkConfig 自动创建 `NodeNetworkConfigurationPolicy`，配置节点级别的网络（桥接、VLAN 等）。

## 2. 工作流程

```
用户定义 NetworkConfig (type: bridge)
    ↓
NMState 创建 NodeNetworkConfigurationPolicy
    ├── 创建 VLAN 接口（如果有 VLAN）
    └── 创建 Linux Bridge
    ↓
Multus 创建 NAD（引用已创建的桥接）
    ↓
KubeVirt VM 使用网络接口
```

## 3. 支持的网络类型

### 3.1 Bridge 网络（需要 NMState）

```yaml
networks:
  - name: management
    type: bridge
    bridgeName: br-mgmt  # 可选，默认使用 br-{network-name}
    vlanId: 100          # 可选，创建 VLAN 接口
    ipConfig:
      mode: static
      address: 192.168.100.10/24
```

**NMState 会创建：**
- VLAN 接口：`ens160.100`（如果指定了 vlanId）
- Linux Bridge：`br-mgmt`（或 `br-management`）


## 4. 配置示例

### 4.1 完整示例（Bridge 网络）

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm-nmstate
spec:
  networks:
    # 默认网络（Pod 网络）
    - name: default
    
    # 管理网络（Bridge + VLAN，使用 NMState）
    - name: management
      type: bridge
      bridgeName: br-mgmt
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
    
    # 外网网络（Bridge，使用 NMState）
    - name: external
      type: bridge
      bridgeName: br-external
      ipConfig:
        mode: static
        address: 192.168.1.200/24
        gateway: 192.168.1.1
```

### 4.2 仅使用 Bridge（全部使用 NMState）

```yaml
networks:
  - name: management
    type: bridge
    bridgeName: br-mgmt
    vlanId: 100
    ipConfig:
      mode: static
      address: 192.168.100.10/24
  
  - name: external
    type: bridge
    bridgeName: br-external
    ipConfig:
      mode: static
      address: 192.168.1.200/24
```

## 5. 实现细节

### 5.1 NMState 策略命名

策略名称格式：`{wukong-name}-{network-name}-bridge`

例如：`ubuntu-vm-nmstate-management-bridge`

### 5.2 桥接名称

- 如果指定了 `bridgeName`，使用指定的名称
- 否则使用默认名称：`br-{network-name}`

### 5.3 VLAN 处理

如果指定了 `vlanId`：
1. NMState 先创建 VLAN 接口：`{physical-interface}.{vlanId}`
2. 然后创建桥接，桥接使用 VLAN 接口作为端口

如果没有 `vlanId`：
- 桥接直接使用物理网卡作为端口

### 5.4 物理网卡

当前实现默认使用 `ens160` 作为物理网卡。

**注意：** 未来可以通过环境变量或配置来指定物理网卡。

## 6. 使用步骤

### 6.1 安装 NMState Operator

```bash
# 设置版本
NMSTATE_VERSION="v0.85.1"

# 安装 kubernetes-nmstate operator（按顺序执行）
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/operator.yaml

# 创建 NMState CR，触发 handler 部署
cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
```

详细安装步骤请参考 [NMSTATE_INSTALLATION.md](./NMSTATE_INSTALLATION.md)。

### 6.2 创建 Wukong CR

```bash
kubectl apply -f vm-with-nmstate.yaml
```

### 6.3 验证

```bash
# 查看 NMState 策略
kubectl get nncp

# 查看策略详情
kubectl get nncp ubuntu-vm-nmstate-management-bridge -o yaml

# 查看节点网络状态
kubectl get nnstate

# 查看 VM 状态
kubectl get vm ubuntu-vm-nmstate
```

## 7. 注意事项

1. **NMState 必须安装**：如果 NMState CRD 不存在，会跳过 NMState 配置
2. **物理网卡名称**：当前默认使用 `ens160`，需要根据实际情况修改
3. **网络顺序**：NMState 先配置节点网络，然后 Multus 创建 NAD
4. **只支持 bridge 和 ovs 类型**：macvlan/ipvlan 类型不支持，会跳过 NMState 配置

## 8. 与 Multus 的配合

- **NMState**：配置节点级别的网络（桥接、VLAN）
- **Multus**：为 Pod/VM 创建网络接口，引用 NMState 创建的桥接

两者配合实现完整的网络管理：
1. NMState 创建底层网络基础设施
2. Multus 使用这些基础设施为 VM 提供网络接口

## 9. 故障排查

### 9.1 NMState 策略未创建

检查：
- NMState Operator 是否安装
- CRD 是否存在：`kubectl get crd | grep nmstate`
- Controller 日志是否有错误

### 9.2 桥接未创建

检查：
- NMState 策略状态：`kubectl get nncp -o yaml`
- 节点网络状态：`kubectl get nnstate <node-name> -o yaml`
- 节点上的实际接口：`ip addr show`

### 9.3 VM 网络接口未配置

检查：
- Multus NAD 是否正确引用桥接名称
- VM 的 Cloud-Init 配置是否正确
- VM 内部的网络接口：`ip addr show`

## 10. 参考

- [NMState 官方文档](https://nmstate.github.io/)
- [NodeNetworkConfigurationPolicy 示例](https://nmstate.github.io/examples/)
- [NMState 作用说明](./NMSTATE_EXPLANATION.md)

