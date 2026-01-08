# NMState 安装和配置指南

## 1. NMState 概述

NMState 是一个 Kubernetes Operator，用于**管理节点级别的网络配置**，包括：

- 创建网络桥接（Linux Bridge）
- 配置 VLAN 接口
- 配置 Bonding（链路聚合）
- 配置 SR-IOV
- 管理网络接口状态

### 1.1 与 Multus 的关系

| 组件 | 作用范围 | 功能 |
|------|---------|------|
| **Multus** | Pod/VM 级别 | 为 Pod/VM 创建额外的网络接口 |
| **NMState** | 节点级别 | 配置节点底层的网络（桥接、VLAN 等） |

### 1.2 工作流程

```
用户定义 NetworkConfig (type: bridge)
    ↓
NMState 创建 NodeNetworkConfigurationPolicy
    ├── 创建 VLAN 接口（如果有 VLAN）
    └── 创建 Linux Bridge
    ↓
Multus 创建 NAD（引用 NMState 创建的桥接）
    ↓
KubeVirt VM 使用网络接口
```

## 2. 安装 NMState Operator

### 2.1 前置要求

- Kubernetes 集群（1.19+）
- `kubectl` 命令行工具
- 节点具有网络配置权限

### 2.1.1 节点级别依赖（重要）

**NMState Operator 需要节点上安装以下依赖：**

1. **NetworkManager**：NMState 依赖 NetworkManager 来管理网络配置
2. **nmstate 包**（可选但推荐）：提供 `nmstatectl` 命令行工具

#### Ubuntu/Debian 安装

**重要说明：** 根据 [nmstate 官方文档](https://nmstate.io/user/install.html)，nmstate 主要支持基于 RPM 的发行版（Fedora、RHEL、CentOS）。Ubuntu/Debian 可能没有官方的 `nmstate` 包。

**方案 1：仅安装 NetworkManager（推荐）**

NMState Handler 容器内已包含 nmstate 工具，节点上只需要 NetworkManager：

```bash
# 更新软件包列表
sudo apt update

# 安装 NetworkManager（必需）
sudo apt install -y network-manager

# 启动并启用 NetworkManager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# 检查 NetworkManager 状态
sudo systemctl status NetworkManager
```

**方案 2：从源码安装 nmstate（可选，用于调试）**

如果需要在节点上使用 `nmstatectl` 命令行工具，可以从源码编译安装：

```bash
# 安装依赖
sudo apt update
sudo apt install -y python3-pip python3-setuptools python3-wheel \
    python3-netaddr python3-dbus python3-gi python3-pyroute2 \
    python3-ruamel-yaml python3-jsonschema \
    libnm-dev libnm-glib-dev libnm-glib-vpn1 libnm-util-dev \
    NetworkManager-dev network-manager-dev

# 克隆源码
git clone https://github.com/nmstate/nmstate.git
cd nmstate

# 安装
sudo PREFIX=/usr make install

# 验证
nmstatectl --version
```

**重要提示：** 
- 对于 Kubernetes NMState Operator，**只需要安装 NetworkManager** 即可
- Handler 容器内已包含 nmstate 工具，**不需要在节点上安装 nmstate 包**
- 如果只是使用 NMState Operator，方案 1（只安装 NetworkManager）即可满足需求
- 从源码安装 nmstate 仅用于在节点上使用 `nmstatectl` 命令行工具调试，不是必需的

#### 配置 Netplan 使用 NetworkManager（Ubuntu 22.04+）

如果使用 `netplan`，需要配置它使用 NetworkManager 作为渲染器：

```bash
# 编辑 netplan 配置
sudo nano /etc/netplan/00-installer-config.yaml
```

配置内容：

```yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens160:
      dhcp4: true
```

应用配置：

```bash
sudo netplan apply
```

#### CentOS/RHEL 安装

```bash
# 安装 NetworkManager 和 nmstate
sudo yum install -y NetworkManager nmstate

# 或者使用 dnf (Fedora/CentOS 8+)
sudo dnf install -y NetworkManager nmstate

# 启动并启用 NetworkManager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
```

#### 验证安装

```bash
# 检查 NetworkManager 是否运行
systemctl status NetworkManager

# 检查 nmstatectl 是否可用
nmstatectl show

# 查看网络接口
nmcli device status
```

**重要说明：**
- **NetworkManager 是必需的**，NMState Handler 依赖它来配置网络
- **Ubuntu/Debian 上可能没有官方的 `nmstate` 包**（根据 [nmstate 官方文档](https://nmstate.io/user/install.html)，主要支持 RPM 发行版）
- **对于 Kubernetes NMState Operator，节点上只需要安装 NetworkManager** 即可
- Handler 容器内已包含 nmstate 工具，**不需要在节点上安装 nmstate 包**
- 如果需要在节点上使用 `nmstatectl` 命令行工具调试，可以从源码编译安装（参见上方方案 2），但这不是必需的

### 2.2 使用 YAML Manifests 安装（推荐）

kubernetes-nmstate 官方推荐使用 YAML manifests 直接安装，而不是 Helm Chart。

#### 方式 1：使用官方发布的 YAML（推荐）

**v0.85.1+ 安装方式（最新）：**

```bash
# 设置版本（请查看最新版本：https://github.com/nmstate/kubernetes-nmstate/releases）
NMSTATE_VERSION="v0.85.1"

# 1. 安装 kubernetes-nmstate operator（按顺序执行）
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/operator.yaml

# 2. 创建 NMState CR，触发 handler 部署
cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

# 3. 等待所有 Pod 就绪
kubectl wait --for=condition=ready pod \
  -l app=nmstate-handler \
  -n nmstate-system \
  --timeout=10m

kubectl wait --for=condition=ready pod \
  -l app=nmstate-operator \
  -n nmstate-system \
  --timeout=10m
```


#### 方式 2：下载后本地安装

如果无法直接访问 GitHub，可以下载后本地安装：

```bash
# 设置版本
NMSTATE_VERSION="v0.85.1"

# 下载所有必需的 YAML 文件
wget https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/nmstate.io_nmstates.yaml
wget https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/namespace.yaml
wget https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/service_account.yaml
wget https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role.yaml
wget https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role_binding.yaml
wget https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/operator.yaml

# 按顺序安装
kubectl apply -f nmstate.io_nmstates.yaml
kubectl apply -f namespace.yaml
kubectl apply -f service_account.yaml
kubectl apply -f role.yaml
kubectl apply -f role_binding.yaml
kubectl apply -f operator.yaml

# 创建 NMState CR
cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

# 等待就绪
kubectl wait --for=condition=ready pod \
  -l app=nmstate-handler \
  -n nmstate-system \
  --timeout=10m
```

#### 方式 3：使用 Operator Lifecycle Manager (OLM)

如果集群已安装 OLM，可以使用 OLM 安装：

```bash
# 创建 OperatorGroup
cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nmstate-operator-group
  namespace: nmstate-system
EOF

# 创建 Subscription
cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubernetes-nmstate-operator
  namespace: nmstate-system
spec:
  channel: stable
  name: kubernetes-nmstate-operator
  source: operatorhubio-catalog
  sourceNamespace: olm
EOF
```

**重要提示：**
- 推荐使用**方式 1**（直接使用官方 YAML），最简单可靠
- 请查看 [kubernetes-nmstate releases](https://github.com/nmstate/kubernetes-nmstate/releases) 获取最新版本号
- 如果使用 OLM，需要先安装 Operator Lifecycle Manager

## 3. 验证安装

> **重要提示：** 在安装 NMState Operator 之前，请确保所有节点上已安装 NetworkManager（参见 2.1.1 节点级别依赖）。节点上不需要安装 nmstate 包（Handler 容器内已包含）。

### 3.1 检查 Pod 状态

```bash
# 检查所有 Pod 是否运行
kubectl get pods -n nmstate-system

# 预期输出：
# NAME                                      READY   STATUS    RESTARTS   AGE
# nmstate-operator-xxxxxxxxx-xxxxx          1/1     Running   0          5m
# nmstate-operator-webhook-xxxxxxxxx-xxxxx  1/1     Running   0          5m
# nmstate-handler-xxxxxxxxx                 1/1     Running   0          5m
```

### 3.2 检查 CRD

```bash
# 检查 CRD 是否存在
kubectl get crd | grep nmstate.io

# 预期输出：
# nodenetworkconfigurationpolicies.nmstate.io
# nodenetworkstates.nmstate.io
```

### 3.3 检查节点网络状态

```bash
# 查看所有节点的网络状态
kubectl get nnstate

# 查看特定节点的网络状态
kubectl get nnstate <node-name> -o yaml
```

### 3.4 检查 Handler 是否正常运行

```bash
# 检查 Handler DaemonSet
kubectl get daemonset -n nmstate-system nmstate-handler

# 检查 Handler Pod 日志
kubectl logs -n nmstate-system -l app=nmstate-handler --tail=50

# 如果日志显示错误，可能是节点缺少 NetworkManager
```

## 4. 配置节点网络

### 4.1 创建 Linux Bridge

创建 `bridge-policy.yaml`：

```yaml
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
            - name: ens160
```

应用：

```bash
kubectl apply -f bridge-policy.yaml
```

### 4.2 创建带 VLAN 的桥接

创建 `bridge-vlan-policy.yaml`：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: management-bridge-vlan
spec:
  desiredState:
    interfaces:
      # 1. 创建 VLAN 接口
      - name: ens160.100
        type: vlan
        state: up
        vlan:
          base-iface: ens160
          id: 100
      
      # 2. 创建桥接，使用 VLAN 接口
      - name: br-mgmt
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens160.100
```

应用：

```bash
kubectl apply -f bridge-vlan-policy.yaml
```

### 4.3 检查策略状态

```bash
# 查看策略
kubectl get nncp

# 查看策略详情
kubectl get nncp management-bridge -o yaml

# 查看策略状态
kubectl get nncp management-bridge -o jsonpath='{.status.conditions}'
```

## 5. 与 VM Operator 集成

### 5.1 自动配置

VM Operator 会根据 `NetworkConfig` 自动创建 `NodeNetworkConfigurationPolicy`。

配置示例：

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
spec:
  networks:
    # 管理网络（Bridge + VLAN）
    - name: management
      type: bridge
      bridgeName: br-mgmt
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
```

VM Operator 会自动：
1. 创建 `NodeNetworkConfigurationPolicy`（通过 NMState）
2. 创建 `NetworkAttachmentDefinition`（通过 Multus）
3. 配置 VM 网络接口

### 5.2 策略命名规则

自动创建的策略名称格式：`{wukong-name}-{network-name}-bridge`

例如：`ubuntu-vm-management-bridge`

### 5.3 查看自动创建的策略

```bash
# 查看所有策略
kubectl get nncp

# 查看特定策略
kubectl get nncp ubuntu-vm-management-bridge -o yaml
```

## 6. 常见配置场景

### 6.1 管理网络（带 VLAN）

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: management-network
spec:
  desiredState:
    interfaces:
      - name: ens160.100
        type: vlan
        state: up
        vlan:
          base-iface: ens160
          id: 100
      - name: br-mgmt
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens160.100
```

### 6.2 数据网络（不带 VLAN）

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: data-network
spec:
  desiredState:
    interfaces:
      - name: br-data
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens161
```

### 6.3 Bonding（链路聚合）

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: bond-network
spec:
  desiredState:
    interfaces:
      - name: bond0
        type: bond
        state: up
        bond:
          mode: active-backup
          port:
            - eth0
            - eth1
      - name: br-bond
        type: linux-bridge
        state: up
        bridge:
          port:
            - name: bond0
```

## 7. 故障排查

### 7.1 NetworkManager 未安装

**问题：** Handler Pod 日志显示无法连接 NetworkManager

**检查：**
```bash
# 在节点上检查 NetworkManager
systemctl status NetworkManager

# 如果未安装，安装它
sudo apt update
sudo apt install -y network-manager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
```

### 7.2 策略未应用

**问题：** 策略一直处于 `Pending` 状态

**检查：**
```bash
# 查看策略状态
kubectl get nncp management-bridge -o yaml

# 查看 Handler 日志
kubectl logs -n nmstate-system -l app=nmstate-handler

# 查看节点网络状态
kubectl get nnstate <node-name> -o yaml
```

**可能原因：**
- 物理网卡名称不正确
- 节点上没有相应的物理网卡
- Handler Pod 未运行

### 7.3 桥接未创建

**问题：** 策略已应用，但桥接未创建

**检查：**
```bash
# 在节点上检查
ssh <node-name>
ip addr show
ip link show br-mgmt

# 查看 Handler 日志
kubectl logs -n nmstate-system -l app=nmstate-handler | grep -i error
```

### 7.4 权限问题

**问题：** Handler 无法配置网络

**检查：**
```bash
# 检查 Handler 是否以特权模式运行
kubectl get daemonset -n nmstate-system nmstate-handler -o yaml | grep -i privileged

# 检查 SELinux 状态（如果启用）
getenforce
```

## 8. 升级和卸载

### 8.1 升级 NMState

```bash
# 设置新版本号
NEW_VERSION="v0.85.1"
OLD_VERSION="v0.84.0"  # 替换为当前安装的版本

# 1. 删除旧版本的资源（按逆序）
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${OLD_VERSION}/operator.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${OLD_VERSION}/role_binding.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${OLD_VERSION}/role.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${OLD_VERSION}/service_account.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${OLD_VERSION}/namespace.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${OLD_VERSION}/nmstate.io_nmstates.yaml

# 2. 安装新版本（按顺序）
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NEW_VERSION}/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NEW_VERSION}/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NEW_VERSION}/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NEW_VERSION}/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NEW_VERSION}/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NEW_VERSION}/operator.yaml

# 3. 如果 NMState CR 不存在，创建它
kubectl get nmstate nmstate || cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

# 4. 等待就绪
kubectl wait --for=condition=ready pod \
  -l app=nmstate-handler \
  -n nmstate-system \
  --timeout=10m
```

### 8.2 卸载 NMState

**注意：** 卸载 NMState 不会删除已配置的网络。如果需要删除网络配置，需要先删除相应的 `NodeNetworkConfigurationPolicy`。

```bash
# 1. 删除所有策略（如果需要）
kubectl delete nncp --all

# 2. 删除 NMState CR（如果存在）
kubectl delete nmstate nmstate

# 3. 卸载 NMState Operator 和 Handler
# 注意：需要替换为实际安装时使用的版本号
NMSTATE_VERSION="v0.85.1"
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/operator.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role_binding.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/service_account.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/namespace.yaml
kubectl delete -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/nmstate.io_nmstates.yaml

# 4. 删除命名空间
kubectl delete namespace nmstate-system
```

## 9. 最佳实践

### 9.1 网络命名

- 使用清晰的命名：`br-mgmt`, `br-data`, `br-external`
- 避免与系统已有网络冲突

### 9.2 VLAN 规划

- 管理网络：VLAN 100-200
- 数据网络：VLAN 200-300
- 存储网络：VLAN 300-400

### 9.3 性能优化

- 禁用 STP（生成树协议）以提升性能（单节点场景）
- 对于多节点，根据需要启用 STP
- 使用专用物理网卡（避免与 Pod 网络冲突）

### 9.4 高可用

- Operator 使用 2 个副本（生产环境）
- Webhook 使用 2 个副本（生产环境）
- Handler 在每个节点运行（DaemonSet）

## 10. 参考文档

- [NMState 官方文档](https://nmstate.github.io/)
- [NodeNetworkConfigurationPolicy 示例](https://nmstate.github.io/examples/)
- [NMState GitHub](https://github.com/nmstate/nmstate)
- [VM Operator NMState 集成](./NMSTATE_INTEGRATION.md)

## 11. 快速开始

### 11.1 节点准备（在所有节点上执行）

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y network-manager

# 启动 NetworkManager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# 验证
systemctl status NetworkManager
nmcli device status
```

**注意：** 只需要安装 `network-manager`，不需要安装 `nmstate` 包（Handler 容器内已包含）。

### 11.2 安装 NMState Operator

```bash
# 1. 设置版本（请查看最新版本：https://github.com/nmstate/kubernetes-nmstate/releases）
NMSTATE_VERSION="v0.85.1"

# 2. 安装 kubernetes-nmstate operator（按顺序执行）
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/operator.yaml

# 3. 创建 NMState CR，触发 handler 部署
cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

# 4. 等待就绪
kubectl wait --for=condition=ready pod \
  -l app=nmstate-handler \
  -n nmstate-system \
  --timeout=10m

kubectl wait --for=condition=ready pod \
  -l app=nmstate-operator \
  -n nmstate-system \
  --timeout=10m
```

### 11.3 验证安装

```bash
# 检查 Pod 状态
kubectl get pods -n nmstate-system

# 检查 CRD
kubectl get crd | grep nmstate.io

# 检查 Handler
kubectl get daemonset -n nmstate-system nmstate-handler

# 检查节点网络状态
kubectl get nnstate
```

### 11.4 创建测试桥接
cat <<EOF | kubectl apply -f -
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: test-bridge
spec:
  desiredState:
    interfaces:
      - name: br-test
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens160
EOF

# 5. 检查状态
kubectl get nncp
kubectl get nnstate
```

---

**注意：** 本文档基于 NMState Operator v0.85.1。不同版本的配置可能略有差异，请参考对应版本的官方文档。

