# Multus kubectl 安装后包含的组件

执行 `./scripts/install-multus-kubectl-k3s.sh` 脚本后会安装以下组件：

## 1. Kubernetes 资源

### 1.1 CustomResourceDefinition (CRD)

```bash
kubectl get crd | grep networkattachment
```

- **networkattachmentdefinitions.k8s.cni.cncf.io**
  - 用途：定义额外的网络接口
  - 允许创建 `NetworkAttachmentDefinition` 资源来定义 Pod 的额外网络

### 1.2 DaemonSet

```bash
kubectl get daemonset -n kube-system kube-multus-ds
```

- **kube-multus-ds** (在 `kube-system` 命名空间)
  - 用途：在每个节点上运行 Multus CNI 守护进程
  - Pod 名称：`kube-multus-ds-<hash>`
  - 数量：每个节点一个 Pod

### 1.3 ServiceAccount

```bash
kubectl get serviceaccount -n kube-system | grep multus
```

- **kube-multus-ds** (在 `kube-system` 命名空间)
  - 用途：DaemonSet Pod 使用的服务账户

### 1.4 ClusterRole

```bash
kubectl get clusterrole | grep multus
```

- **multus** 或 **kube-multus-ds**
  - 用途：定义 Multus 需要的集群级别权限
  - 权限包括：
    - 读取/创建/更新/删除 `NetworkAttachmentDefinition` CRD
    - 读取 Pod、Node 等资源

### 1.5 ClusterRoleBinding

```bash
kubectl get clusterrolebinding | grep multus
```

- **multus** 或 **kube-multus-ds**
  - 用途：将 ClusterRole 绑定到 ServiceAccount

## 2. 配置文件

### 2.1 Multus 主配置文件

**位置**: `/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf`

```json
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig",
  "confDir": "/etc/cni/multus/net.d",
  "cniDir": "/var/lib/cni/multus",
  "binDir": "/opt/cni/bin",
  "logFile": "/var/log/multus.log",
  "logLevel": "verbose",
  "clusterNetwork": "default",
  ...
}
```

**用途**:
- 定义 Multus CNI 插件的配置
- 指定默认网络（clusterNetwork）
- 配置日志、目录等参数

### 2.2 Daemon 配置文件 (Thick Plugin)

**位置**: `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json`

```json
{
  "binDir": "/opt/cni/bin",
  "confDir": "/etc/cni/net.d",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log"
}
```

**用途**:
- Multus Thick Plugin 的 daemon 配置
- 定义 daemon 进程的参数

### 2.3 Kubeconfig 文件

**位置**: `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig`

**用途**:
- Multus 用于与 Kubernetes API Server 通信
- 允许 Multus 读取 `NetworkAttachmentDefinition` CRD

## 3. CNI 二进制文件

### 3.1 Multus CNI 插件

**位置**: `/var/lib/rancher/k3s/data/cni/` (新版本) 或 `/var/lib/rancher/k3s/data/current/bin/` (旧版本)

**文件**:
- `multus`
- `multus-daemon` (Thick Plugin)

**用途**:
- Multus CNI 插件二进制文件
- 由 Multus DaemonSet Pod 的 init container 安装

## 4. 目录结构

安装后的目录结构：

```
/var/lib/rancher/k3s/agent/etc/cni/net.d/
├── 00-multus.conf                    # Multus 主配置文件
├── 10-flannel.conflist              # 默认 CNI (Flannel)
└── multus.d/
    ├── daemon-config.json            # Daemon 配置
    └── multus.kubeconfig            # Kubeconfig

/var/lib/rancher/k3s/data/cni/        # CNI 二进制目录 (新版本)
├── multus                           # Multus CNI 插件
├── multus-daemon                    # Multus Daemon (Thick Plugin)
└── ... (其他 CNI 插件)
```

## 5. 验证安装

### 检查所有组件

```bash
# 1. 检查 CRD
kubectl get crd | grep networkattachment

# 2. 检查 DaemonSet
kubectl get daemonset -n kube-system kube-multus-ds

# 3. 检查 Pod
kubectl get pods -n kube-system -l app=multus

# 4. 检查 ServiceAccount
kubectl get serviceaccount -n kube-system kube-multus-ds

# 5. 检查 ClusterRole
kubectl get clusterrole | grep multus

# 6. 检查 ClusterRoleBinding
kubectl get clusterrolebinding | grep multus

# 7. 检查配置文件
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/

# 8. 检查 CNI 二进制文件
sudo ls -la /var/lib/rancher/k3s/data/cni/ | grep multus
# 或
sudo ls -la /var/lib/rancher/k3s/data/current/bin/ | grep multus
```

### 检查 Pod 状态

```bash
# 查看 Pod 详情
kubectl describe pod -n kube-system -l app=multus

# 查看 Pod 日志
kubectl logs -n kube-system -l app=multus

# 检查 Pod 是否正常运行
kubectl get pods -n kube-system -l app=multus
# 应该看到所有 Pod 都是 Running 状态
```

## 6. 功能

安装 Multus 后，您可以：

1. **创建 NetworkAttachmentDefinition**: 定义额外的网络接口
2. **在 Pod 中使用额外网络**: 通过注解 `k8s.v1.cni.cncf.io/networks` 为 Pod 添加额外的网络接口
3. **多网络支持**: 允许 Pod 拥有多个网络接口（管理网、业务网等）

## 7. 示例：创建 NetworkAttachmentDefinition

```bash
# 创建示例 NetworkAttachmentDefinition
cat <<EOF | kubectl apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-conf
  namespace: default
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.1.0/24",
        "rangeStart": "192.168.1.200",
        "rangeEnd": "192.168.1.216",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ],
        "gateway": "192.168.1.1"
      }
    }
EOF

# 验证创建
kubectl get networkattachmentdefinition
```

## 8. 卸载

如果要卸载 Multus：

```bash
# 删除 DaemonSet（会自动删除 Pod）
kubectl delete daemonset -n kube-system kube-multus-ds

# 删除配置文件（可选）
sudo rm -f /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
sudo rm -rf /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d

# 删除 CRD（会删除所有 NetworkAttachmentDefinition）
kubectl delete crd networkattachmentdefinitions.k8s.cni.cncf.io

# 删除其他资源
kubectl delete serviceaccount -n kube-system kube-multus-ds
kubectl delete clusterrole multus 2>/dev/null || kubectl delete clusterrole kube-multus-ds
kubectl delete clusterrolebinding multus 2>/dev/null || kubectl delete clusterrolebinding kube-multus-ds
```

## 总结

执行脚本后会安装：

✅ **Kubernetes 资源**:
- 1 个 CRD (NetworkAttachmentDefinition)
- 1 个 DaemonSet (每个节点运行 Multus Pod)
- 1 个 ServiceAccount
- 1 个 ClusterRole
- 1 个 ClusterRoleBinding

✅ **配置文件**:
- Multus 主配置文件 (`00-multus.conf`)
- Daemon 配置文件 (`daemon-config.json`)
- Kubeconfig 文件

✅ **二进制文件**:
- Multus CNI 插件
- Multus Daemon (Thick Plugin)

这些组件共同实现了 Multus CNI 的功能，允许 Pod 拥有多个网络接口。

