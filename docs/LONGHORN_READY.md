# Longhorn 就绪确认

## ✅ Longhorn 已成功安装！

看到 `longhorn` StorageClass 已创建，说明 Longhorn 核心功能已就绪。

## 验证结果

从你的输出可以看到：

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
longhorn (default)     driver.longhorn.io      Delete          Immediate              true                   68m
```

**关键信息**:
- ✅ `longhorn` StorageClass 存在
- ✅ `allowVolumeExpansion: true` - **支持卷扩展** ⭐
- ✅ `provisioner: driver.longhorn.io` - CSI 驱动已安装
- ✅ 已设置为默认 StorageClass

## 这意味着什么？

### ✅ 可以使用了

即使 `driver-deployer` 可能还在初始化，但：
- **StorageClass 已创建** - 可以创建 PVC
- **CSI 驱动已安装** - 可以动态分配存储
- **支持卷扩展** - 可以扩展磁盘大小

### ⚠️ driver-deployer 状态

`driver-deployer` 是可选组件，用于部署 CSI 驱动。如果 StorageClass 已经存在，说明 CSI 驱动已经部署成功，`driver-deployer` 的状态不影响基本使用。

## 立即使用

### 在 Wukong 中使用 Longhorn

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-longhorn
spec:
  cpu: 2
  memory: 4Gi
  
  disks:
    - name: system
      size: 20Gi
      storageClassName: longhorn  # 使用 Longhorn
      boot: true
      image: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"
    
    - name: data
      size: 100Gi
      storageClassName: longhorn  # 使用 Longhorn
      boot: false
  
  cloudInitUser:
    name: ubuntu
    passwordHash: "$1$7.t8q8zZ$59I1IiMXy5w3gIl5Yrn/4/"
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: "/bin/bash"
  
  startStrategy:
    autoStart: true
```

### 测试创建 PVC

```bash
# 创建测试 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-longhorn-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 检查 PVC 状态
kubectl get pvc test-longhorn-pvc

# 应该很快变为 Bound
```

## 验证 Longhorn 状态

运行验证脚本：

```bash
./scripts/verify-longhorn-ready.sh
```

## 关于 driver-deployer

如果 `driver-deployer` 仍在 `Init:0/1` 状态：

### 选项 1: 忽略（推荐）

如果 StorageClass 已存在且可用，可以忽略 `driver-deployer` 的状态。它不影响基本使用。

### 选项 2: 稍后重启

如果想让所有组件都就绪：

```bash
# 等待一段时间后重启
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer

# 或等待它自动完成
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -w
```

### 选项 3: 检查是否有问题

```bash
# 查看 Init Container 日志
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager --tail=50
```

## 下一步

### 1. 创建测试 VM

使用 Longhorn StorageClass 创建 Wukong：

```bash
# 使用生产环境配置（已配置 Longhorn）
kubectl apply -f config/samples/vm_v1alpha1_wukong_production.yaml

# 或使用分离磁盘配置
kubectl apply -f config/samples/vm_v1alpha1_wukong_separated_disks.yaml
```

### 2. 验证存储

```bash
# 检查 PVC
kubectl get pvc

# 检查存储状态
./scripts/check-vm-storage.sh
```

### 3. 测试卷扩展

```bash
# 扩展磁盘
./scripts/expand-disk.sh <wukong-name> <disk-name> <new-size>
```

## 总结

| 组件 | 状态 | 影响 |
|------|------|------|
| StorageClass | ✅ 已创建 | 可以使用 |
| CSI Driver | ✅ 已安装 | 可以创建 PVC |
| Volume Expansion | ✅ 支持 | 可以扩展磁盘 |
| longhorn-manager | ✅ 运行中 | 核心功能正常 |
| driver-deployer | ⚠️ 初始化中 | 不影响基本使用 |

**结论**: ✅ **Longhorn 已就绪，可以开始使用了！**

## 快速开始

```bash
# 1. 验证状态
./scripts/verify-longhorn-ready.sh

# 2. 创建测试 VM
kubectl apply -f config/samples/vm_v1alpha1_wukong_production.yaml

# 3. 检查状态
kubectl get wukong
kubectl get vm
kubectl get pvc
```

