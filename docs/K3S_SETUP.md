# k3s 环境部署指南

## 前置条件检查清单

在 Ubuntu 虚拟机上运行 Wukong Operator，需要以下组件：

### ✅ 必需组件

1. **k3s** - Kubernetes 集群
2. **KubeVirt** - 虚拟机管理
3. **CDI (Containerized Data Importer)** - 数据导入工具
4. **Wukong Operator** - 我们的自定义 Operator

### ⚠️ 可选组件（根据需求）

- **Multus CNI** - 多网络支持（如果 Wukong 配置了 networks）
- **NMState Operator** - 节点网络配置（如果 Wukong 配置了需要 NMState 的网络）

## 快速部署步骤

### 1. 安装 k3s

```bash
# 安装 k3s
curl -sfL https://get.k3s.io | sh -

# 检查状态
sudo systemctl status k3s
```

### 2. 配置 kubeconfig

**重要**：`make run` 需要在本地运行，必须配置 kubeconfig：

```bash
# 方法 1: 复制 k3s kubeconfig 到用户目录
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# 方法 2: 设置 KUBECONFIG 环境变量
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 验证连接
kubectl get nodes
```

**注意**：如果 k3s.yaml 中的 server 地址是 `127.0.0.1` 或 `localhost`，从远程访问时需要修改为实际的 IP 地址。

### 3. 安装 KubeVirt

```bash
# 设置版本
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 安装 KubeVirt Operator
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

# 等待 Operator 就绪
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s

# 安装 KubeVirt CR
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

# 等待 KubeVirt 就绪
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=300s
```

### 4. 安装 CDI

```bash
# 设置版本
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 安装 CDI Operator
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

# 等待 Operator 就绪
kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s

# 安装 CDI CR
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 等待 CDI 就绪
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s
```

### 5. 配置 KubeVirt（如果需要）

在 k3s 环境中，通常需要配置 `useEmulation: true`（如果硬件不支持 KVM）：

```bash
kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

### 6. 安装 Wukong CRD

```bash
# 在项目目录中
cd /path/to/novasphere

# 安装 CRD
make install
```

### 7. 运行 Wukong Operator

```bash
# 确保 kubeconfig 已配置
export KUBECONFIG=~/.kube/config
# 或者
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 运行 controller
make run
```

## 验证安装

### 检查所有组件状态

```bash
# 1. 检查 k3s
sudo systemctl status k3s

# 2. 检查 KubeVirt
kubectl get pods -n kubevirt
kubectl get kubevirt -n kubevirt

# 3. 检查 CDI
kubectl get pods -n cdi
kubectl get cdi -n cdi

# 4. 检查 Wukong CRD
kubectl get crd wukongs.vm.novasphere.dev

# 5. 检查节点标签（KubeVirt 需要）
kubectl get nodes --show-labels | grep kubevirt.io/schedulable
```

### 如果节点没有 `kubevirt.io/schedulable=true` label

```bash
# 添加 label
kubectl label node <node-name> kubevirt.io/schedulable=true
```

## 常见问题

### 问题 1: `make run` 报错 "unable to load in-cluster config"

**原因**：kubeconfig 未配置或路径不正确

**解决**：
```bash
# 检查 kubeconfig
echo $KUBECONFIG
kubectl config view

# 如果为空，设置 kubeconfig
export KUBECONFIG=~/.kube/config
# 或
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 验证连接
kubectl get nodes
```

### 问题 2: k3s.yaml 中的 server 地址是 localhost

如果从远程访问或使用不同的网络接口，需要修改：

```bash
# 查看当前配置
cat ~/.kube/config | grep server

# 如果需要修改，编辑配置文件
# 将 127.0.0.1 或 localhost 改为实际的 IP 地址或主机名
```

### 问题 3: 权限问题

如果遇到权限问题：

```bash
# 确保 kubeconfig 文件权限正确
chmod 600 ~/.kube/config

# 如果使用 sudo 安装的 k3s，可能需要
sudo chown $USER:$USER /etc/rancher/k3s/k3s.yaml
```

## 完整检查脚本

```bash
#!/bin/bash

echo "=== 1. 检查 k3s ==="
sudo systemctl status k3s --no-pager | head -5

echo -e "\n=== 2. 检查 kubeconfig ==="
if [ -z "$KUBECONFIG" ]; then
    echo "KUBECONFIG 未设置，使用默认路径 ~/.kube/config"
    export KUBECONFIG=~/.kube/config
fi
kubectl config view --minify 2>/dev/null && echo "✓ kubeconfig 配置正确" || echo "✗ kubeconfig 配置错误"

echo -e "\n=== 3. 检查集群连接 ==="
kubectl get nodes 2>/dev/null && echo "✓ 集群连接正常" || echo "✗ 无法连接集群"

echo -e "\n=== 4. 检查 KubeVirt ==="
kubectl get pods -n kubevirt 2>/dev/null | grep -E "virt-operator|virt-controller|virt-handler" | head -5
kubectl get kubevirt -n kubevirt 2>/dev/null && echo "✓ KubeVirt 已安装" || echo "✗ KubeVirt 未安装"

echo -e "\n=== 5. 检查 CDI ==="
kubectl get pods -n cdi 2>/dev/null | grep -E "cdi-operator|cdi-apiserver|cdi-deployment" | head -5
kubectl get cdi -n cdi 2>/dev/null && echo "✓ CDI 已安装" || echo "✗ CDI 未安装"

echo -e "\n=== 6. 检查 Wukong CRD ==="
kubectl get crd wukongs.vm.novasphere.dev 2>/dev/null && echo "✓ Wukong CRD 已安装" || echo "✗ Wukong CRD 未安装"

echo -e "\n=== 7. 检查节点 label ==="
kubectl get nodes --show-labels 2>/dev/null | grep kubevirt.io/schedulable && echo "✓ 节点已标记为可调度" || echo "⚠ 节点未标记为可调度（可能需要添加 label）"
```

## 下一步

安装完成后：

1. **运行 `make run`** 启动 controller
2. **创建 Wukong 资源**：
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```
3. **观察状态**：
   ```bash
   kubectl get wukong
   kubectl get vm
   kubectl get vmi
   kubectl get pods | grep virt-launcher
   ```

## 依赖总结

### 必需依赖

- ✅ k3s
- ✅ KubeVirt
- ✅ CDI

### 可选依赖（根据 Wukong 配置）

- ⚠️ Multus CNI（如果 Wukong 配置了 `networks`）
- ⚠️ NMState Operator（如果 Wukong 配置了需要 NMState 的网络）

### 不需要的依赖

- ❌ 不需要额外的 StorageClass（k3s 自带 local-path）
- ❌ 不需要额外的网络插件（k3s 自带 Flannel）
- ❌ 不需要额外的监控工具（可选）

