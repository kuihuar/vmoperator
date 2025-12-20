# Multus CNI 安装指南

本文档详细说明如何在 k3s 集群中安装和配置 Multus CNI，以便与 VM Operator 项目配合使用。

## 📋 概述

Multus CNI 是一个 Kubernetes CNI 元插件，允许 Pod（包括虚拟机）拥有多个网络接口。这对于 VM Operator 项目至关重要，因为：

- 虚拟机通常需要多个网络接口（管理网、业务网等）
- 支持不同的网络类型（Bridge、Macvlan、SR-IOV、OVS）
- 支持 VLAN、静态 IP 等高级网络配置

参考：[Multus CNI 官方仓库](https://github.com/k8snetworkplumbingwg/multus-cni)

## 🚀 快速安装（推荐）

### 方法 1: 使用 Thick Plugin（推荐）

Thick Plugin 是 Multus 4.0+ 引入的新部署方式，提供更多功能（如指标监控）：

```bash
# 一键安装 Multus CNI
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
```

### 方法 2: 使用 Thin Plugin（资源受限环境）

如果您的环境资源有限，可以使用 Thin Plugin：

```bash
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
```

### 方法 3: 从本地文件安装

如果您想使用特定版本或离线安装：

```bash
# 克隆仓库
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git
cd multus-cni

# 安装 Thick Plugin
cat ./deployments/multus-daemonset-thick.yml | kubectl apply -f -

# 或安装 Thin Plugin
cat ./deployments/multus-daemonset.yml | kubectl apply -f -

cd ..
```

## ✅ 验证安装

### 1. 检查 Pod 状态

```bash
# 检查 Multus DaemonSet 是否运行
kubectl get pods -n kube-system | grep multus

# 应该看到类似输出：
# kube-multus-ds-amd64-xxxxx   1/1     Running   0          2m
```

### 2. 检查 CRD

```bash
# 检查 NetworkAttachmentDefinition CRD 是否安装
kubectl get crd | grep networkattachment

# 应该看到：
# networkattachmentdefinitions.k8s.cni.cncf.io
```

### 3. 检查 CNI 配置

```bash
# 在节点上检查 CNI 配置（需要 SSH 到节点）
# 对于 k3s，配置文件通常在：
ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

# 应该看到 multus 相关的配置文件
```

### 4. 查看 Multus 日志

```bash
# 查看 Multus Pod 日志
kubectl logs -n kube-system -l app=multus --tail=50
```

## 🔧 在 k3s 中的特殊配置

### k3s 默认 CNI

k3s 默认使用 Flannel 作为默认 CNI。Multus 会自动检测并使用它作为默认网络。

### 验证默认网络

```bash
# 检查 Flannel 是否运行
kubectl get pods -n kube-system | grep flannel

# 检查 CNI 配置
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist
```

## 📝 创建测试 NetworkAttachmentDefinition

安装完成后，可以创建一个测试 NAD 来验证功能：

```bash
cat <<EOF | kubectl apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: test-bridge
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-test",
      "ipam": {
        "type": "dhcp"
      }
    }
EOF
```

验证：

```bash
# 查看 NAD
kubectl get networkattachmentdefinition -n default

# 查看详情
kubectl describe networkattachmentdefinition test-bridge -n default
```

## 🔗 与 VM Operator 集成

### 自动检测

VM Operator 会自动检测 Multus 是否安装：

- ✅ **已安装**: 自动创建 `NetworkAttachmentDefinition` 资源
- ❌ **未安装**: 优雅降级，使用默认 Pod 网络

### 使用方式

在 `VirtualMachineProfile` 中配置网络：

```yaml
apiVersion: vm.vmoperator.dev/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: test-vm
spec:
  cpu: 2
  memory: 4Gi
  networks:
    # 方式 1: 自动创建 NAD（如果未指定 nadName）
    - name: mgmt
      type: bridge
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
    
    # 方式 2: 使用已存在的 NAD
    - name: business
      nadName: existing-nad-name
      ipConfig:
        mode: dhcp
  disks:
    - name: system
      size: 20Gi
      storageClassName: local-path
```

### 网络类型支持

VM Operator 支持以下网络类型：

| 类型 | 说明 | 配置示例 |
|------|------|----------|
| `bridge` | 桥接网络 | 支持 VLAN、静态 IP、DHCP |
| `macvlan` | Macvlan 网络 | 直接连接到物理网络 |
| `sriov` | SR-IOV 网络 | 高性能网络（需要 SR-IOV 支持） |
| `ovs` | Open vSwitch | 软件定义网络 |

## 🐛 故障排查

### 问题 1: Multus Pod 无法启动

**症状**:
```bash
kubectl get pods -n kube-system | grep multus
# kube-multus-ds-amd64-xxxxx   0/1     CrashLoopBackOff
```

**排查步骤**:

```bash
# 1. 查看 Pod 日志
kubectl logs -n kube-system -l app=multus --tail=100

# 2. 检查节点 CNI 配置目录权限
# 在节点上执行
sudo ls -la /opt/cni/bin/
sudo ls -la /etc/cni/net.d/

# 3. 检查节点资源
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

**常见原因**:
- CNI 配置目录权限不足
- 节点资源不足
- 与现有 CNI 冲突

### 问题 2: NetworkAttachmentDefinition 创建失败

**症状**:
```
Error: no matches for kind "NetworkAttachmentDefinition" in version "k8s.cni.cncf.io/v1"
```

**解决方案**:

```bash
# 1. 确认 CRD 已安装
kubectl get crd networkattachmentdefinitions.k8s.cni.cncf.io

# 2. 如果不存在，重新安装 Multus
kubectl delete -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# 3. 等待 CRD 就绪
kubectl wait --for condition=established --timeout=60s crd/networkattachmentdefinitions.k8s.cni.cncf.io
```

### 问题 3: Pod 无法获取额外网络接口

**症状**: Pod 创建成功，但只有默认网络接口

**排查步骤**:

```bash
# 1. 检查 Pod 注解
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations}' | jq

# 应该看到类似：
# "k8s.v1.cni.cncf.io/networks": "[{\"name\":\"test-bridge\"}]"

# 2. 检查 Multus 日志
kubectl logs -n kube-system -l app=multus --tail=100 | grep <pod-name>

# 3. 在节点上检查网络接口
# SSH 到节点，进入 Pod 网络命名空间
kubectl exec -it <pod-name> -- ip addr show
```

### 问题 4: k3s 特定问题

**CNI 配置路径**:

k3s 使用不同的 CNI 配置路径：
- 默认路径: `/var/lib/rancher/k3s/agent/etc/cni/net.d/`
- 二进制路径: `/var/lib/rancher/k3s/data/current/bin/`

**检查方法**:

```bash
# 在节点上执行
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
```

## 🔄 升级 Multus

### 升级到最新版本

```bash
# 1. 备份当前配置（可选）
kubectl get networkattachmentdefinition -A -o yaml > nad-backup.yaml

# 2. 删除旧版本
kubectl delete -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# 3. 安装新版本
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# 4. 验证
kubectl get pods -n kube-system | grep multus
```

## 📚 参考资源

- [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Multus 快速开始指南](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/quickstart.md)
- [Multus 配置文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/configuration.md)
- [VM Operator 网络配置](DEVELOPMENT.md#网络管理模块)

## ✅ 安装检查清单

完成安装后，请确认：

- [ ] Multus DaemonSet Pod 在所有节点上运行
- [ ] `NetworkAttachmentDefinition` CRD 已安装
- [ ] 可以创建和查看 NAD 资源
- [ ] VM Operator 可以检测到 Multus（查看 Controller 日志）
- [ ] 测试创建带有额外网络的 Pod/VM

---

**提示**: 如果在生产环境使用，建议：
1. 使用特定版本而非 `master` 分支
2. 在生产环境测试前先在开发环境验证
3. 备份现有网络配置

