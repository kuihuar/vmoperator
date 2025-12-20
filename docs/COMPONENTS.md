# 完整组件清单

本文档列出了实现定制虚拟机开发项目所需的所有组件，包括核心组件和辅助组件。

## 📋 组件分类

### 一、核心必需组件（已包含）

这些是项目运行的核心组件，已在主文档中说明：

| 组件 | 版本 | 作用 | 状态 |
|------|------|------|------|
| **k3s** | >= 1.24 | Kubernetes 集群基础 | ✅ 已包含 |
| **kubebuilder** | >= 3.0 | Operator 开发框架 | ✅ 已包含 |
| **KubeVirt** | >= 0.58 | 虚拟机运行时 | ✅ 已包含 |
| **CDI** | >= 1.57 | 容器化数据导入工具 | ✅ 已包含 |
| **Multus CNI** | >= 3.9 | 多网络接口支持 | ✅ 已包含 |
| **NMState Operator** | >= 0.73 | 节点网络配置 | ✅ 已包含 |
| **华美存储 CSI** | 厂商版本 | 持久化存储 | ✅ 已包含 |

---

## 🔧 二、KubeVirt 依赖组件（必需）

KubeVirt 运行需要以下底层组件，通常随 KubeVirt 一起安装：

### 2.1 CDI (Containerized Data Importer)

**作用**: KubeVirt 的数据导入/导出工具，用于从镜像创建磁盘、克隆磁盘等

**版本**: >= 1.57.0（与 KubeVirt 版本匹配）

**安装**:
```bash
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 安装 CDI
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 等待就绪
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s
```

**关键资源**:
- `DataVolume`: 用于从镜像创建磁盘
- `DataSource`: 数据源定义

**使用场景**:
- 从容器镜像创建虚拟机磁盘（`spec.disks[].image`）
- 磁盘克隆
- 磁盘导入/导出

---

### 2.2 默认 CNI 插件

**作用**: Multus 需要依赖一个默认 CNI 作为主网络接口

**选项**:
- **Flannel** (k3s 默认): 简单易用，适合开发环境
- **Calico**: 功能强大，支持网络策略
- **Cilium**: 高性能，支持 eBPF

**k3s 默认使用 Flannel**，通常无需额外安装。如需更换：

```bash
# 使用 Calico（示例）
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

---

### 2.3 节点虚拟化支持

**作用**: KubeVirt 在节点上运行虚拟机需要虚拟化支持

**要求**:
- CPU 支持虚拟化扩展（Intel VT-x / AMD-V）
- 内核模块：`kvm`, `kvm_intel` 或 `kvm_amd`

**检查**:
```bash
# 检查 CPU 虚拟化支持
grep -E 'vmx|svm' /proc/cpuinfo

# 检查内核模块
lsmod | grep kvm

# 如果没有加载，手动加载
sudo modprobe kvm
sudo modprobe kvm_intel  # Intel
# 或
sudo modprobe kvm_amd    # AMD
```

---

## 🌐 三、网络相关组件（可选但推荐）

### 3.1 DHCP 服务器

**作用**: 当使用 DHCP 模式配置网络时，需要 DHCP 服务器

**选项**:
- **dnsmasq**: 轻量级，适合小规模
- **ISC DHCP**: 功能完整
- **外部 DHCP 服务器**: 使用现有网络基础设施

**安装 dnsmasq (示例)**:
```bash
# 在节点上安装
sudo apt-get install dnsmasq  # Ubuntu/Debian
sudo yum install dnsmasq       # CentOS/RHEL

# 配置 DHCP（根据实际网络调整）
sudo vim /etc/dnsmasq.conf
```

**在 Multus 中使用**:
```yaml
# NetworkAttachmentDefinition 配置
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "ipam": {
        "type": "dhcp"  # 使用 DHCP
      }
    }
```

---

### 3.2 MetalLB（如果需要 LoadBalancer）

**作用**: 为虚拟机提供 LoadBalancer 类型的服务（如果需要）

**版本**: >= 0.13.0

**安装**:
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# 配置 IP 地址池
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.200
EOF
```

**使用场景**: 如果需要为虚拟机提供外部访问（通常不需要）

---

## 💾 四、存储相关组件（可选）

### 4.1 本地存储（开发测试）

**作用**: 如果华美存储不可用，可以使用本地存储进行开发测试

**选项**:
- **Local Path Provisioner** (k3s 自带)
- **OpenEBS LocalPV**
- **Rook Ceph** (完整存储方案)

**使用 Local Path Provisioner**:
```bash
# k3s 默认已包含，创建 StorageClass
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
EOF
```

---

### 4.2 快照和克隆支持

**作用**: 如果需要磁盘快照和克隆功能

**组件**:
- **VolumeSnapshot CRD**: Kubernetes 快照 API
- **CSI Snapshotter**: CSI 驱动的快照支持

**安装**:
```bash
# 安装 VolumeSnapshot CRD
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
```

**注意**: 需要华美存储 CSI 驱动支持快照功能

---

## 🔍 五、监控和可观测性（推荐）

### 5.1 Prometheus Operator

**作用**: 监控虚拟机、网络、存储等组件的指标

**版本**: >= 0.68.0

**安装**:
```bash
# 使用 Helm（推荐）
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# 或使用 Operator
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml
```

**监控指标**:
- VM 运行状态
- CPU/内存使用率
- 网络流量
- 存储使用量

---

### 5.2 Grafana

**作用**: 可视化监控指标

**通常随 Prometheus Operator 一起安装**

**访问**:
```bash
# 获取访问地址
kubectl get svc -n default grafana
kubectl get secret -n default grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

---

### 5.3 日志收集（可选）

**选项**:
- **Loki + Promtail**: 轻量级日志聚合
- **ELK Stack**: 完整日志解决方案
- **Fluentd/Fluent Bit**: 日志收集器

**安装 Loki（示例）**:
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack
```

---

## 🛠️ 六、开发工具（必需）

### 6.1 代码生成工具

**作用**: kubebuilder 项目需要这些工具生成代码

**工具**:
- **controller-gen**: 生成 CRD 和 RBAC
- **kustomize**: 管理 Kubernetes 配置
- **go**: Go 语言环境

**安装**:
```bash
# controller-gen
go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest

# kustomize
go install sigs.k8s.io/kustomize/kustomize/v5@latest

# 验证
controller-gen --version
kustomize version
```

---

### 6.2 镜像构建工具

**选项**:
- **Docker**: 传统容器构建
- **Buildah**: 无需守护进程
- **Podman**: 兼容 Docker 的替代品

**安装 Docker**:
```bash
# macOS
brew install docker

# Linux
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

---

### 6.3 镜像仓库（可选）

**作用**: 存储 Operator 镜像和 VM 镜像

**选项**:
- **Docker Hub**: 公共仓库
- **Harbor**: 私有仓库
- **GitHub Container Registry**: GitHub 集成
- **本地仓库**: 开发测试

**使用本地仓库（开发）**:
```bash
# 启动本地 registry
docker run -d -p 5000:5000 --name registry registry:2

# 标记镜像
docker tag vmoperator:latest localhost:5000/vmoperator:latest

# 推送
docker push localhost:5000/vmoperator:latest
```

---

## 🔐 七、安全相关组件（生产环境必需）

### 7.1 Cert Manager

**作用**: 自动管理 TLS 证书（如果 Operator 需要 HTTPS）

**版本**: >= 1.13.0

**安装**:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

**使用场景**: 
- Operator Webhook 需要 TLS
- 外部 API 需要 HTTPS

---

### 7.2 RBAC 配置

**作用**: 控制 Operator 的权限

**kubebuilder 会自动生成**，但需要检查：

```bash
# 查看 ClusterRole
kubectl get clusterrole vmoperator-manager-role -o yaml

# 查看 ClusterRoleBinding
kubectl get clusterrolebinding vmoperator-manager-rolebinding -o yaml
```

---

## 📦 八、容器运行时（k3s 自带）

k3s 默认使用 **containerd**，通常无需额外配置。

**检查**:
```bash
# 查看容器运行时
kubectl get nodes -o wide
sudo crictl version
```

---

## 🧪 九、测试工具（开发推荐）

### 9.1 测试框架

- **ginkgo**: BDD 测试框架
- **gomega**: 断言库
- **envtest**: Kubernetes API 测试环境

**安装**:
```bash
go install github.com/onsi/ginkgo/v2/ginkgo@latest
```

---

### 9.2 调试工具

- **kubectl debug**: 调试 Pod
- **virtctl**: KubeVirt 命令行工具
- **virt-viewer**: 虚拟机控制台

**安装 virtctl**:
```bash
# 下载 virtctl
VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")
VERSION=${VERSION%+*}
echo ${VERSION}
wget -O virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64
chmod +x virtctl
sudo mv virtctl /usr/local/bin/
```

**使用**:
```bash
# 查看 VM 控制台
virtctl console <vm-name>

# SSH 到 VM
virtctl ssh <vm-name>

# 查看 VM 状态
virtctl get vmis
```

---

## 📊 组件依赖关系图

```
k3s (基础)
  ├── containerd (容器运行时)
  ├── Flannel (默认 CNI)
  │
  ├── KubeVirt
  │   ├── CDI (数据导入)
  │   ├── libvirt (底层虚拟化)
  │   └── QEMU (虚拟机运行时)
  │
  ├── Multus CNI
  │   └── 依赖默认 CNI (Flannel)
  │
  ├── NMState Operator
  │   └── 节点网络配置
  │
  ├── 华美存储 CSI
  │   └── StorageClass
  │
  └── VM Operator (本项目)
      ├── kubebuilder (开发框架)
      ├── controller-gen (代码生成)
      └── kustomize (配置管理)
```

---

## ✅ 安装检查清单

### 核心组件
- [ ] k3s 已安装并运行
- [ ] KubeVirt 已安装并运行
- [ ] CDI 已安装并运行
- [ ] Multus CNI 已安装并运行
- [ ] NMState Operator 已安装并运行
- [ ] 华美存储 CSI 已安装并配置

### 开发工具
- [ ] kubectl 已安装
- [ ] kubebuilder 已安装
- [ ] Go >= 1.19 已安装
- [ ] controller-gen 已安装
- [ ] kustomize 已安装
- [ ] Docker/Buildah 已安装

### 网络支持
- [ ] 默认 CNI (Flannel) 运行正常
- [ ] 节点虚拟化支持已启用 (kvm 模块)
- [ ] DHCP 服务器已配置（如使用 DHCP）

### 存储支持
- [ ] 华美存储 StorageClass 已创建
- [ ] 本地存储 StorageClass 已创建（备用）

### 监控（可选）
- [ ] Prometheus 已安装
- [ ] Grafana 已安装

### 验证命令

```bash
# 检查所有组件状态
echo "=== k3s ==="
kubectl get nodes

echo "=== KubeVirt ==="
kubectl get pods -n kubevirt

echo "=== CDI ==="
kubectl get pods -n cdi

echo "=== Multus ==="
kubectl get pods -n kube-system | grep multus

echo "=== NMState ==="
kubectl get pods -n nmstate

echo "=== 存储 ==="
kubectl get storageclass

echo "=== 虚拟化支持 ==="
lsmod | grep kvm

echo "=== 开发工具 ==="
kubectl version --client
kubebuilder version
go version
controller-gen --version
```

---

## 📝 组件版本兼容性

| 组件 | 推荐版本 | 最低版本 | 说明 |
|------|---------|---------|------|
| k3s | 1.28+ | 1.24 | 最新稳定版 |
| KubeVirt | 1.1+ | 0.58 | 与 k3s 版本匹配 |
| CDI | 1.57+ | 1.50 | 与 KubeVirt 版本匹配 |
| Multus | 4.0+ | 3.9 | 最新稳定版 |
| NMState | 0.73+ | 0.70 | 最新稳定版 |
| kubebuilder | 3.14+ | 3.0 | 最新稳定版 |
| Go | 1.21+ | 1.19 | 最新稳定版 |

---

## 🔗 相关资源

- [KubeVirt 组件文档](https://kubevirt.io/user-guide/operations/installation/)
- [CDI 文档](https://kubevirt.io/user-guide/operations/containerized_data_importer/)
- [Multus 文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NMState 文档](https://nmstate.github.io/)

---

**文档版本**: v1.0.0  
**最后更新**: 2024-01-01

