# 安装清单和步骤

本文档记录 k3s 环境下的完整安装步骤和组件清单。

## 安装顺序

```
1. k3s (基础集群)
   ↓
2. CDI (Containerized Data Importer)
   ↓
3. KubeVirt (虚拟化层)
   ↓
4. Ceph/Rook (存储)
   ↓
5. Multus CNI (可选，仅用于 VM 多网卡)
```

---

## 步骤 1: 安装 k3s

### 安装命令

```bash
sudo ./scripts/install-k3s-only.sh
```

### 验证

```bash
# 检查节点
kubectl get nodes

# 检查 k3s 版本
k3s --version

# 检查系统 Pods
kubectl get pods -n kube-system
```

### 安装后状态

- ✅ k3s 服务运行中
- ✅ 节点状态: Ready
- ✅ 默认 CNI: Flannel
- ✅ kubeconfig: ~/.kube/config

---

## 步骤 2: 安装 CDI

### 安装命令

```bash
# 设置版本
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 或者使用固定版本
export CDI_VERSION=v1.62.0

# 安装 CDI Operator
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

# 等待 Operator 就绪
kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s

# 安装 CDI CR
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 等待 CDI 就绪
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s
```

### 验证

```bash
kubectl get pods -n cdi
kubectl get cdi -n cdi
```

### 预期状态

- ✅ cdi-operator: Running
- ✅ cdi-apiserver: Running
- ✅ cdi-deployment: Running
- ✅ cdi-uploadproxy: Running
- ✅ CDI CR 状态: Available

---

## 步骤 3: 安装 KubeVirt

### 安装命令

```bash
# 设置版本
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 或者使用固定版本
export KUBEVIRT_VERSION=v1.2.0

# 安装 KubeVirt Operator
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

# 等待 Operator 就绪
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s

# 安装 KubeVirt CR
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

# 等待 KubeVirt 就绪
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s
```

### k3s 环境配置

```bash
# 启用软件模拟（如果硬件不支持 KVM）
kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

# 添加节点 label
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME kubevirt.io/schedulable=true --overwrite
```

### 验证

```bash
kubectl get pods -n kubevirt
kubectl get kubevirt -n kubevirt
```

### 预期状态

- ✅ virt-operator: Running
- ✅ virt-controller: Running
- ✅ virt-handler: Running
- ✅ virt-api: Running
- ✅ KubeVirt CR 状态: Deployed

---

## 步骤 4: 安装 Ceph/Rook

### 安装命令

```bash
sudo ./scripts/install-ceph-rook.sh
```

### 安装选项

脚本会询问：
- 部署方式：选择 `2`（使用目录存储，适合开发/测试）

### 验证

```bash
# 检查 Rook Operator
kubectl get pods -n rook-ceph

# 检查 Ceph Cluster
kubectl get cephcluster -n rook-ceph

# 检查 StorageClass
kubectl get storageclass
```

### 预期状态

- ✅ rook-ceph-operator: Running
- ✅ Ceph Cluster 状态: Ready
- ✅ StorageClass: rook-ceph-block

---

## 步骤 5: 安装 Multus CNI（可选）

**注意**：Multus 仅用于 VM 的多网卡功能，不是必需的。如果不需要多网卡，可以跳过。

### 安装时机

- ✅ 等基础设施（Ceph、KubeVirt）都稳定后再安装
- ✅ 配置为 secondary CNI，不影响默认网络

### 安装方法

参考：`docs/COMPLETE_INSTALLATION_GUIDE.md` 中的 Multus 安装部分

---

## 组件清单

### 已安装组件

| 组件 | 命名空间 | 状态 | 版本 |
|------|---------|------|------|
| k3s | - | ✅ Running | - |
| CDI | cdi | ⏳ 待安装 | - |
| KubeVirt | kubevirt | ⏳ 待安装 | - |
| Ceph/Rook | rook-ceph | ⏳ 待安装 | - |
| Multus CNI | kube-system | ⏳ 可选 | - |

### 检查命令

```bash
# 检查所有组件
echo "=== k3s ==="
kubectl get nodes

echo "=== CDI ==="
kubectl get pods -n cdi 2>/dev/null || echo "未安装"

echo "=== KubeVirt ==="
kubectl get pods -n kubevirt 2>/dev/null || echo "未安装"

echo "=== Ceph ==="
kubectl get pods -n rook-ceph 2>/dev/null || echo "未安装"

echo "=== Multus ==="
kubectl get pods -n kube-system -l app=multus 2>/dev/null || echo "未安装"
```

---

## 配置文件位置

### k3s

- kubeconfig: `~/.kube/config` 或 `/etc/rancher/k3s/k3s.yaml`
- 数据目录: `/var/lib/rancher/k3s`
- 配置文件: `/etc/rancher/k3s/k3s.yaml`

### CNI

- 配置目录: `/var/lib/rancher/k3s/agent/etc/cni/net.d`
- 默认 CNI: Flannel

---

## 常见问题

### 问题 1: kubeconfig 中的 server 地址是 127.0.0.1

**解决**：
```bash
# 如果需要从远程访问，修改 server 地址
sed -i 's/127.0.0.1/你的节点IP/g' ~/.kube/config
```

### 问题 2: KubeVirt Pods 无法启动

**检查**：
- 节点是否有 `kubevirt.io/schedulable=true` label
- 是否启用了软件模拟（k3s 环境通常需要）

### 问题 3: Ceph Operator 无法启动

**检查**：
- 是否还有 Multus 配置残留
- 网络是否正常
- 资源是否充足

---

## 下一步

安装完所有组件后：

1. **验证环境**：
   ```bash
   kubectl get pods -A
   ```

2. **创建第一个 VM**：
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble.yaml
   ```

3. **测试存储**：
   ```bash
   kubectl apply -f config/ceph-test-pvc.yaml
   ```

---

**最后更新**: 2025-12-22

