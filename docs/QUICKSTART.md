# 快速开始指南

本指南将帮助您快速搭建开发环境并运行第一个虚拟机。

## 前置检查清单

在开始之前，请确保您已准备好以下环境：

- [ ] Linux 或 macOS 开发机器
- [ ] 支持虚拟化的 CPU（Intel VT-x 或 AMD-V）
- [ ] 至少 8GB 内存（推荐 16GB+）
- [ ] 至少 50GB 可用磁盘空间
- [ ] 网络连接（用于下载依赖）

## 步骤 1: 安装基础工具

### 安装 kubectl

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### 安装 kubebuilder

```bash
# macOS
brew install kubebuilder

# Linux
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && sudo mv kubebuilder /usr/local/bin/
```

### 安装 Go

```bash
# macOS
brew install go

# Linux
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
```

### 验证安装

```bash
kubectl version --client
kubebuilder version
go version
```

## 步骤 2: 安装 k3s

```bash
# 快速安装
curl -sfL https://get.k3s.io | sh -

# 设置 kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# 验证
kubectl get nodes
```

## 步骤 3: 安装依赖组件

### 3.1 安装 KubeVirt

```bash
# 设置版本
export VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 安装
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml

# 等待就绪（约 2-3 分钟）
kubectl wait -n kubevirt kv kubevirt --for condition=Available --timeout=300s

# 验证
kubectl get pods -n kubevirt
```

### 3.2 安装 Multus CNI

```bash
# 克隆仓库
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git
cd multus-cni

# 安装
cat ./deployments/multus-daemonset-thick.yml | kubectl apply -f -

# 验证
kubectl get pods -n kube-system | grep multus
cd ..
```

### 3.3 安装 NMState Operator

```bash
# 创建命名空间
kubectl create namespace nmstate

# 安装
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.73.0/nmstate-operator.yaml

# 等待就绪
kubectl wait -n nmstate --for=condition=ready pod -l app=kubernetes-nmstate-operator --timeout=300s

# 验证
kubectl get pods -n nmstate
```

### 3.4 配置华美存储

> **注意**: 根据华美存储厂商提供的文档进行安装和配置。

```bash
# 示例：创建 StorageClass（请根据实际文档调整）
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: huamei-sc-ssd
provisioner: huamei.csi.storage
parameters:
  type: ssd
EOF

# 验证
kubectl get storageclass
```

## 步骤 4: 初始化 VM Operator 项目

```bash
# 进入项目目录
cd /Users/jianfenliu/Workspace/vmoperator

# 初始化 kubebuilder 项目
kubebuilder init --domain=example.com --repo=github.com/your-org/vmoperator

# 创建 API
kubebuilder create api --group=vm --version=v1alpha1 --kind=VirtualMachineProfile
# 选择: Y (创建 Resource) 和 Y (创建 Controller)
```

## 步骤 5: 验证环境

运行以下命令验证所有组件已正确安装：

```bash
# 检查 k3s
kubectl get nodes

# 检查 KubeVirt
kubectl get pods -n kubevirt

# 检查 Multus
kubectl get pods -n kube-system | grep multus

# 检查 NMState
kubectl get pods -n nmstate

# 检查存储
kubectl get storageclass
```

所有组件应该都处于 `Running` 状态。

## 步骤 6: 运行第一个测试

### 6.1 创建测试资源

```bash
# 创建命名空间
kubectl create namespace vm-test

# 创建简单的 VirtualMachineProfile（需要先完成代码开发）
kubectl apply -f config/samples/vm_v1alpha1_virtualmachineprofile.yaml
```

### 6.2 检查状态

```bash
# 查看 VirtualMachineProfile
kubectl get vmprofile -n vm-test

# 查看详情
kubectl describe vmprofile -n vm-test

# 查看相关资源
kubectl get vm,vmi,pvc -n vm-test
```

## 常见问题

### Q1: k3s 安装失败

**A**: 检查系统要求：
- 确保有 root 权限
- 检查防火墙设置
- 查看日志：`sudo journalctl -u k3s`

### Q2: KubeVirt 无法启动

**A**: 检查虚拟化支持：
```bash
# 检查 CPU 虚拟化支持
grep -E 'vmx|svm' /proc/cpuinfo

# 检查内核模块
lsmod | grep kvm
```

### Q3: Multus 网络配置失败

**A**: 检查 CNI 配置：
```bash
# 查看 CNI 配置
ls -la /etc/cni/net.d/

# 检查 Multus 日志
kubectl logs -n kube-system -l app=multus
```

### Q4: 存储无法绑定

**A**: 检查存储配置：
```bash
# 查看 PVC 状态
kubectl get pvc

# 查看存储类
kubectl describe storageclass huamei-sc-ssd

# 检查 CSI 驱动
kubectl get pods -n kube-system | grep csi
```

## 下一步

完成环境搭建后，您可以：

1. 阅读 [开发文档](DEVELOPMENT.md) 了解详细架构
2. 阅读 [API 文档](API.md) 了解资源定义
3. 开始实现 Controller 逻辑

## 获取帮助

如果遇到问题，请：

1. 查看组件日志
2. 检查 [故障排查指南](DEVELOPMENT.md#故障排查)
3. 提交 Issue 到项目仓库

---

**提示**: 建议在开发环境中使用，生产环境请参考完整的部署文档。

