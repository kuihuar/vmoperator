# Multus 为什么会影响 Ceph？

## 问题根源

在 k3s 中，当 Multus 安装后，如果 Multus 的配置文件（`00-multus.conf`）被放在 CNI 配置目录（`/var/lib/rancher/k3s/agent/etc/cni/net.d/`）中，k3s 的 CNI 插件链会调用 Multus。

**关键点**：Multus 作为 **meta plugin**，即使 Pod 没有明确使用 Multus 网络（没有 `NetworkAttachmentDefinition` 注解），也会被调用来处理**所有 Pod 的网络设置**。

## 为什么 Ceph Pod 会受影响？

1. **Multus 作为默认 CNI 链的一部分**
   - k3s 的 CNI 配置目录中，按字母顺序加载配置文件
   - `00-multus.conf` 会被 k3s 识别为 CNI 配置
   - 所有 Pod 创建时，kubelet 都会调用 Multus CNI 插件

2. **Multus 需要 kubeconfig**
   - Multus 在初始化时需要访问 Kubernetes API Server
   - 它需要 kubeconfig 文件来获取 NetworkAttachmentDefinition 资源
   - **即使 Pod 不使用额外网络，Multus 也会读取 kubeconfig**

3. **如果 kubeconfig 路径错误、文件不存在或权限问题**
   - Multus 初始化失败
   - **所有 Pod 的创建都会失败**（包括 Ceph Pod）
   - 常见错误信息：
     - `failed to get context for the kubeconfig /etc/cni/net.d/multus.d/multus.kubeconfig: no such file or directory`
     - `permission denied`（权限问题）
   
4. **权限问题（重要）**
   - k3s 的 `/var/lib/rancher/k3s/agent` 目录权限为 `700` (drwx------)
   - 只有 root 用户可以访问该目录
   - 如果 Multus Pod 不是以 root 运行，**无法访问 kubeconfig 文件**
   - 导致所有 Pod 创建失败

## 解决方案

### 方案 0：检查并修复权限问题（首要）

**权限问题是最常见的原因！**

1. **检查权限**
   ```bash
   sudo ./scripts/check-multus-permissions.sh
   ```

2. **修复权限**
   ```bash
   sudo ./scripts/fix-multus-permissions.sh
   ```

3. **验证修复**
   - 检查 Multus Pod 是否以 root 运行
   - 检查 Pod 内是否可以访问 kubeconfig 文件

详细说明请参考：[MULTUS_PERMISSIONS_ISSUE.md](./MULTUS_PERMISSIONS_ISSUE.md)

### 方案 1：修复 Multus kubeconfig 配置

确保 Multus 的 kubeconfig 文件存在且路径正确。

**关键配置点**：

1. **DaemonSet 挂载配置**
   ```yaml
   volumes:
     - name: cni
       hostPath:
         path: /var/lib/rancher/k3s/agent/etc/cni/net.d  # k3s CNI 配置目录
   volumeMounts:
     - name: cni
       mountPath: /host/etc/cni/net.d  # Pod 内的挂载点
   ```

2. **Multus 配置文件中的路径**
   - 配置文件：`/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf`
   - kubeconfig 路径（Pod 内）：`/host/etc/cni/net.d/multus.d/multus.kubeconfig`
   - 主机路径：`/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig`

3. **确保文件存在**
   ```bash
   # 创建 kubeconfig 文件
   sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d
   sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
   sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' \
     /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
   sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
   ```

### 方案 2：暂时禁用 Multus（如果不需要）

如果暂时不需要 Multus，可以：

1. **删除或重命名 Multus 配置文件**
   ```bash
   sudo mv /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf \
           /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf.disabled
   ```

2. **删除 Multus DaemonSet**
   ```bash
   kubectl delete daemonset -n kube-system kube-multus-ds
   ```

3. **重启受影响的 Pod**
   ```bash
   kubectl delete pods -n rook-ceph --all --force --grace-period=0
   ```

### 方案 3：使用 Helm 正确安装 Multus（长期方案）

Helm chart 会自动处理路径配置，避免手动配置错误。

## 配置规划

### 完整的 Multus 配置检查清单

在安装或修复 Multus 前，确认以下配置：

#### 1. k3s CNI 配置目录
```bash
# k3s 的 CNI 配置目录
CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
```

#### 2. Multus 配置文件
```bash
# Multus 主配置文件
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# 检查配置中的 kubeconfig 路径
sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig'
```

#### 3. DaemonSet 挂载配置
```bash
# 检查 DaemonSet 挂载
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}'
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}'
```

#### 4. kubeconfig 文件路径对应关系

| 位置 | 路径 |
|------|------|
| 配置文件中的路径（Pod 内） | `/host/etc/cni/net.d/multus.d/multus.kubeconfig` |
| DaemonSet 挂载点（Pod 内） | `/host/etc/cni/net.d` |
| DaemonSet 主机路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d` |
| 实际主机文件路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig` |

**关键公式**：
```
配置文件中的路径 = DaemonSet挂载点(Pod内) + "/multus.d/multus.kubeconfig"
实际主机路径 = DaemonSet主机路径 + "/multus.d/multus.kubeconfig"
```

#### 5. 验证配置

```bash
# 1. 检查配置文件
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | jq '.kubeconfig'

# 2. 检查文件是否存在
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 3. 检查 Pod 内访问
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/multus.d/multus.kubeconfig
```

## 推荐的安装流程

1. **先确定是否需要 Multus**
   - 如果只需要 Ceph，可以先不安装 Multus
   - 如果需要多网络接口（如虚拟机场景），才需要 Multus

2. **如果安装 Multus，使用 Helm**
   - Helm chart 会自动处理路径配置
   - 避免手动配置错误

3. **验证 Multus 不影响其他组件**
   - 安装后测试创建普通 Pod
   - 确认 Ceph 等组件可以正常启动

4. **如果出现问题，先禁用 Multus**
   - 让其他组件先运行起来
   - 再单独处理 Multus 配置

## 总结

**Multus 影响 Ceph 的原因**：
- Multus 作为 meta plugin，会被 k3s 调用处理所有 Pod 的网络
- Multus 初始化时需要 kubeconfig
- 如果 kubeconfig 配置错误，所有 Pod（包括 Ceph）都无法创建

**解决思路**：
1. 确保 Multus 的 kubeconfig 配置正确（文件存在、路径匹配）
2. 或者暂时禁用 Multus（如果不需要）
3. 使用 Helm 安装可以避免大部分配置问题

