# VM 创建前检查清单

## 1. 前置条件检查

### 1.1 检查 Multus 是否安装

```bash
# 检查 Multus CRD
kubectl get crd | grep network-attachment-definitions

# 检查 Multus DaemonSet
kubectl get daemonset -n kube-system | grep multus

# 检查 Multus Pod 状态
kubectl get pods -n kube-system | grep multus
```

**预期输出：**
- CRD: `network-attachment-definitions.k8s.cni.cncf.io`
- DaemonSet: `kube-multus-ds` 状态为 `1/1`
- Pod: `kube-multus-ds-xxx` 状态为 `Running`

### 1.2 检查 NMState 是否安装

```bash
# 检查 NMState CRD
kubectl get crd | grep nmstate

# 检查 NMState Pod 状态
kubectl get pods -n nmstate-system

# 检查 NMState CR
kubectl get nmstate
```

**预期输出：**
- CRD: `nodenetworkconfigurationpolicies.nmstate.io`
- Pod: `nmstate-operator-xxx` 和 `nmstate-handler-xxx` 状态为 `Running`
- CR: `nmstate` 资源存在

**如果 NMState 未安装，请先安装：**

```bash
# 设置版本
NMSTATE_VERSION="v0.85.1"

# 安装 NMState Operator
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/${NMSTATE_VERSION}/operator.yaml

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

### 1.3 检查节点 NetworkManager

```bash
# 在节点上检查 NetworkManager
systemctl status NetworkManager

# 如果未安装，安装它（Ubuntu/Debian）
sudo apt update
sudo apt install -y network-manager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
```

### 1.4 检查 Longhorn StorageClass

```bash
# 检查 Longhorn StorageClass
kubectl get sc | grep longhorn

# 检查 Longhorn Pod 状态
kubectl get pods -n longhorn-system | grep -E "manager|engine"
```

**预期输出：**
- StorageClass: `longhorn` 存在
- Pod: Longhorn 相关 Pod 状态为 `Running`

### 1.5 检查 VM Operator Controller

```bash
# 检查 Wukong CRD
kubectl get crd | grep wukong

# 检查 Controller Pod（如果在集群中运行）
kubectl get pods -n novasphere-system 2>/dev/null || echo "Controller 可能通过 make run 本地运行"
```

## 2. 配置文件检查

### 2.1 检查网络配置

**重要：** 当前只支持 `bridge` 和 `ovs` 类型，不支持 `macvlan`。

```yaml
networks:
  - name: default  # 默认网络，使用 Pod 网络
  
  - name: management
    type: bridge  # ✅ 正确：使用 bridge
    bridgeName: "br-management"  # 可选
    ipConfig:
      mode: static
      address: "192.168.100.10/24"
      gateway: "192.168.100.1"
  
  - name: external
    type: bridge  # ✅ 正确：使用 bridge
    bridgeName: "br-external"  # 可选
    ipConfig:
      mode: static
      address: "192.168.1.200/24"
      gateway: "192.168.1.1"
```

### 2.2 检查 IP 地址冲突

```bash
# 检查 IP 是否已被占用
ping 192.168.100.10
ping 192.168.1.200

# 检查物理网卡名称
ip addr show | grep -E "^[0-9]+:" | grep -v lo
```

### 2.3 检查镜像 URL

确保镜像 URL 可访问：

```bash
curl -I http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img
```

## 3. 创建 VM

### 3.1 应用配置文件

```bash
# 应用 VM 配置
kubectl apply -f config/samples/vm_v1alpha1_wukong_dual_network.yaml
```

### 3.2 检查创建状态

```bash
# 查看 Wukong 状态
kubectl get wukong ubuntu-vm-dual-network

# 查看 VM 状态
kubectl get vm ubuntu-vm-dual-network

# 查看 VMI 状态
kubectl get vmi ubuntu-vm-dual-network

# 查看 NMState 策略（自动创建）
kubectl get nncp | grep ubuntu-vm-dual-network

# 查看 Multus NAD（自动创建）
kubectl get net-attach-def | grep ubuntu-vm-dual-network
```

### 3.3 检查 Pod 状态

```bash
# 查看 virt-launcher Pod
kubectl get pods | grep ubuntu-vm-dual-network

# 查看 Pod 日志
kubectl logs -f <virt-launcher-pod-name>
```

## 4. 验证网络

### 4.1 检查 VM IP

```bash
# 查看 VMI 网络接口
kubectl get vmi ubuntu-vm-dual-network -o jsonpath='{.status.interfaces[*].ipAddress}'

# 查看 VMI 详细信息
kubectl get vmi ubuntu-vm-dual-network -o yaml | grep -A 10 "interfaces:"
```

### 4.2 测试网络连接

```bash
# 进入 VM（如果已配置 SSH）
ssh ubuntu@192.168.100.10
ssh ubuntu@192.168.1.200

# 在 VM 内检查网络
ip addr show
ip route show
```

## 5. 故障排查

### 5.1 VM 一直处于 Starting 状态

```bash
# 检查 virt-launcher Pod 日志
kubectl logs <virt-launcher-pod-name>

# 检查 virt-handler 日志
kubectl logs -n kubevirt -l app=virt-handler --tail=100 | grep ubuntu-vm-dual-network

# 检查 NMState 策略状态
kubectl get nncp -o yaml | grep -A 20 "ubuntu-vm-dual-network"
```

### 5.2 网络接口未创建

```bash
# 检查 NMState 策略是否已应用
kubectl get nncp ubuntu-vm-dual-network-management-bridge -o yaml

# 检查节点网络状态
kubectl get nnstate <node-name> -o yaml

# 在节点上检查桥接
ssh <node-name>
ip addr show br-management
ip addr show br-external
```

### 5.3 Multus NAD 未创建

```bash
# 检查 Controller 日志（如果通过 make run 运行）
# 查看是否有错误信息

# 检查 Multus CRD
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io
```

## 6. 参考文档

- [NMState 安装指南](./NMSTATE_INSTALLATION.md)
- [NMState 集成说明](./NMSTATE_INTEGRATION.md)
- [Multus 网络流程](./MULTUS_NETWORK_FLOW.md)

