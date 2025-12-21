# k3s 官方方式安装 Multus

根据 [k3s 官方文档](https://docs.k3s.io/networking/multus-ipams) 和 [Multus Thick Plugin 文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/thick-plugin.md) 安装 Multus。

## 重要说明

### k3s CNI 路径

**新版本 (2024年10月及之后)**:
- CNI 二进制路径: `/var/lib/rancher/k3s/data/cni/` (固定路径)
- 适用于: v1.28.15+k3s1, v1.29.10+k3s1, v1.30.6+k3s1, v1.31.2+k3s1

**旧版本**:
- CNI 二进制路径: `/var/lib/rancher/k3s/data/current/bin/` (每次升级会变)

**CNI 配置目录** (所有版本):
- `/var/lib/rancher/k3s/agent/etc/cni/net.d`

### 推荐使用 rke2-multus Chart

k3s 官方推荐使用 `rke2-multus` Helm Chart，而不是 `k8snetworkplumbingwg/multus`。

## 安装步骤

### 方法 1: 使用安装脚本（推荐）

```bash
./scripts/install-multus-k3s-official.sh
```

### 方法 2: 手动安装

#### 步骤 1: 添加 Helm Repository

```bash
helm repo add rke2-charts https://rke2-charts.rancher.io
helm repo update
```

#### 步骤 2: 准备 values 文件

使用 `config/multus-values-k3s.yaml`，或创建新文件：

```yaml
config:
  fullnameOverride: multus
  cni_conf:
    confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
    binDir: /var/lib/rancher/k3s/data/cni/
    kubeconfig: /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
    multusAutoconfigDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
```

#### 步骤 3: 安装 Multus

```bash
helm install multus rke2-charts/rke2-multus \
    --namespace kube-system \
    --create-namespace \
    --values config/multus-values-k3s.yaml \
    --wait \
    --timeout 10m
```

## 配置选项

### 基础配置（必需）

```yaml
config:
  fullnameOverride: multus
  cni_conf:
    confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
    binDir: /var/lib/rancher/k3s/data/cni/
    kubeconfig: /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
    multusAutoconfigDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
```

### 启用 Whereabouts IPAM

```yaml
config:
  fullnameOverride: multus
  cni_conf:
    confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
    binDir: /var/lib/rancher/k3s/data/cni/
    kubeconfig: /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
    multusAutoconfigDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
rke2-whereabouts:
  fullnameOverride: whereabouts
  enabled: true
  cniConf:
    confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
    binDir: /var/lib/rancher/k3s/data/cni/
```

### 启用 DHCP IPAM

```yaml
config:
  fullnameOverride: multus
  cni_conf:
    confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
    binDir: /var/lib/rancher/k3s/data/cni/
    kubeconfig: /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
    multusAutoconfigDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
manifests:
  dhcpDaemonSet: true
```

## 使用 Multus

安装完成后，可以创建 `NetworkAttachmentDefinition` 资源，并在 Pod 中使用。

### 示例: 创建 NetworkAttachmentDefinition

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-whereabouts
spec:
  config: |-
    {
      "cniVersion": "1.0.0",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "ipam": {
        "type": "whereabouts",
        "range": "172.17.0.0/24",
        "gateway": "172.17.0.1",
        "configuration_path": "/var/lib/rancher/k3s/agent/etc/cni/net.d/whereabouts.d/whereabouts.conf"
      }
    }
```

### 示例: 在 Pod 中使用

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multus-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: multus-demo
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: macvlan-whereabouts@eth1
      labels:
        app: multus-demo
    spec:
      containers:
      - name: shell
        image: busybox:1.36
        command: ["sleep", "3600"]
```

## 验证安装

```bash
# 检查 Pod 状态
kubectl get pods -n kube-system -l app=multus

# 检查 DaemonSet
kubectl get daemonset -n kube-system -l app=multus

# 检查 CRD
kubectl get crd | grep networkattachment

# 查看日志
kubectl logs -n kube-system -l app=multus
```

## 卸载

```bash
helm uninstall multus -n kube-system
```

## 参考文档

- [k3s Multus 文档](https://docs.k3s.io/networking/multus-ipams)
- [Multus Thick Plugin 文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/thick-plugin.md)
- [Multus 配置参考](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/configuration.md)

