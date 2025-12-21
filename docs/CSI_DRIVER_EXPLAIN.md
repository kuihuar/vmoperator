# CSI Driver 说明

## 什么是 CSI Driver？

CSI (Container Storage Interface) Driver 是 Kubernetes 存储插件的标准接口。它允许存储提供商（如 Longhorn）与 Kubernetes 集成，实现动态存储管理。

## CSI Driver 的作用

### 1. 动态创建 PV（PersistentVolume）

当您创建 PVC（PersistentVolumeClaim）时，CSI Driver 会：
- 接收 Kubernetes 的存储请求
- 与 Longhorn Manager 通信
- 创建 Longhorn Volume
- 创建对应的 PV
- 将 PV 绑定到 PVC

### 2. 挂载/卸载存储卷

当 Pod 需要使用存储时，CSI Driver 会：
- 在节点上挂载 Longhorn Volume
- 将卷暴露给 Pod
- 当 Pod 删除时，卸载卷

### 3. 存储卷生命周期管理

CSI Driver 负责：
- 创建卷（CreateVolume）
- 删除卷（DeleteVolume）
- 扩展卷（ExpandVolume）
- 快照管理（CreateSnapshot, DeleteSnapshot）

## Longhorn CSI Driver 组件

Longhorn CSI Driver 包含以下组件：

### 1. CSI Attacher

**作用**: 处理卷的 attach/detach 操作

**组件**:
- `longhorn-csi-attacher` Deployment
- 监听 PVC/PV 的 attach/detach 请求
- 与 Longhorn Manager 通信

### 2. CSI Provisioner

**作用**: 动态创建 PV

**组件**:
- `longhorn-csi-provisioner` Deployment
- 监听 PVC 创建请求
- 调用 Longhorn Manager API 创建卷

### 3. CSI Resizer

**作用**: 扩展存储卷

**组件**:
- `longhorn-csi-resizer` Deployment
- 处理 PVC 扩展请求

### 4. CSI Driver Node Plugin

**作用**: 在节点上挂载/卸载卷

**组件**:
- `longhorn-csi-plugin` DaemonSet（每个节点一个）
- 在节点上执行实际的挂载操作

## 为什么 CSI Driver 没有安装？

### 可能原因

1. **Longhorn 安装不完整**
   - `longhorn-driver-deployer` 未完成
   - CSI 组件未部署

2. **`longhorn-driver-deployer` 卡住**
   - Init Container 等待 `longhorn-backend` API
   - 无法创建 CSI 组件

3. **Longhorn Manager 未就绪**
   - Manager 未运行
   - Manager API 不可用

4. **资源不足**
   - 节点资源不足
   - 无法调度 CSI Pods

## 检查 CSI Driver 状态

### 1. 检查 CSI 相关 Pods

```bash
kubectl get pods -n longhorn-system | grep -E "csi|driver"
```

**应该看到**:
- `longhorn-csi-attacher-*`
- `longhorn-csi-provisioner-*`
- `longhorn-csi-resizer-*`
- `longhorn-csi-plugin-*` (DaemonSet，每个节点一个)

### 2. 检查 CSI Driver 资源

```bash
# CSI Driver 对象
kubectl get csidriver

# 应该看到: driver.longhorn.io
```

### 3. 检查 `longhorn-driver-deployer`

```bash
kubectl get pods -n longhorn-system | grep driver-deployer
kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true
```

## 解决方案

### 方案 1: 等待 `longhorn-driver-deployer` 完成

如果 `longhorn-driver-deployer` 还在运行，等待它完成：

```bash
# 检查状态
kubectl get pods -n longhorn-system | grep driver-deployer

# 查看日志
kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true
```

### 方案 2: 重启 `longhorn-driver-deployer`

如果 `longhorn-driver-deployer` 卡住：

```bash
# 删除 Pod，让它重新创建
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer

# 等待重新创建
kubectl get pods -n longhorn-system | grep driver-deployer
```

### 方案 3: 手动创建 CSI 组件

如果 `longhorn-driver-deployer` 无法完成，可以手动创建 CSI 组件（不推荐，除非确定问题）。

### 方案 4: 重新安装 Longhorn

如果所有方法都失败：

```bash
# 卸载 Longhorn
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 清理
kubectl delete namespace longhorn-system

# 重新安装
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

## 验证 CSI Driver 安装

### 1. 检查 CSI Driver 对象

```bash
kubectl get csidriver
```

**应该看到**:
```
NAME                 ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
driver.longhorn.io   true             false            false             <unset>         false                Persistent   5m
```

### 2. 检查 CSI Pods

```bash
kubectl get pods -n longhorn-system | grep csi
```

**应该看到**:
- `longhorn-csi-attacher-*` (Running)
- `longhorn-csi-provisioner-*` (Running)
- `longhorn-csi-resizer-*` (Running)
- `longhorn-csi-plugin-*` (Running，每个节点一个)

### 3. 测试 PVC 创建

```bash
# 创建测试 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# 检查 PVC 状态
kubectl get pvc test-pvc

# 应该很快变为 Bound
```

## 总结

| 组件 | 作用 | 状态检查 |
|------|------|----------|
| CSI Driver | Kubernetes 存储接口 | `kubectl get csidriver` |
| CSI Attacher | 处理 attach/detach | `kubectl get pods -n longhorn-system \| grep csi-attacher` |
| CSI Provisioner | 动态创建 PV | `kubectl get pods -n longhorn-system \| grep csi-provisioner` |
| CSI Resizer | 扩展卷 | `kubectl get pods -n longhorn-system \| grep csi-resizer` |
| CSI Plugin | 节点挂载/卸载 | `kubectl get pods -n longhorn-system \| grep csi-plugin` |

**关键点**:
- ✅ CSI Driver 是 Longhorn 与 Kubernetes 集成的桥梁
- ✅ 没有 CSI Driver，PVC 无法被 provision，会一直 Pending
- ✅ `longhorn-driver-deployer` 负责创建 CSI 组件
- ✅ 如果 `driver-deployer` 卡住，CSI Driver 不会安装

## 快速诊断

```bash
# 1. 检查 CSI Driver
kubectl get csidriver

# 2. 检查 CSI Pods
kubectl get pods -n longhorn-system | grep csi

# 3. 检查 driver-deployer
kubectl get pods -n longhorn-system | grep driver-deployer
kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true

# 4. 如果 driver-deployer 卡住，重启它
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

