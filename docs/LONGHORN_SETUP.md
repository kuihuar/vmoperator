# Longhorn 存储安装和使用指南

## 概述

Longhorn 是一个轻量级、可靠且功能强大的分布式块存储系统，专为 Kubernetes 设计，特别适合 k3s 环境。

### 为什么选择 Longhorn？

- ✅ **专为 Kubernetes 设计**: 原生 Kubernetes 存储解决方案
- ✅ **支持卷扩展**: `allowVolumeExpansion: true`
- ✅ **高可用性**: 数据自动复制到多个节点
- ✅ **易于管理**: 提供 Web UI 界面
- ✅ **自动备份**: 支持快照和备份
- ✅ **轻量级**: 资源占用小，适合边缘和中小规模环境

## 安装步骤

### 方法 1: 使用安装脚本（推荐）

```bash
# 运行安装脚本
./scripts/setup-longhorn.sh
```

脚本会自动：
1. 检查 k3s 环境
2. 安装 Longhorn
3. 等待组件就绪
4. 验证 StorageClass

### 方法 2: 手动安装

```bash
# 1. 安装 Longhorn
LONGHORN_VERSION="v1.6.0"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml

# 2. 等待安装完成
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 3. 验证 StorageClass
kubectl get storageclass longhorn
```

## 验证安装

### 1. 检查 Longhorn 组件

```bash
# 查看所有 Longhorn Pods
kubectl get pods -n longhorn-system

# 应该看到以下组件运行：
# - longhorn-manager-*
# - longhorn-ui-*
# - longhorn-driver-deployer-*
# - longhorn-csi-plugin-*
```

### 2. 检查 StorageClass

```bash
# 查看 StorageClass
kubectl get storageclass longhorn

# 验证支持卷扩展
kubectl get storageclass longhorn -o yaml | grep allowVolumeExpansion
# 应该输出: allowVolumeExpansion: true
```

### 3. 检查 Longhorn UI

```bash
# 端口转发到 Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# 然后在浏览器中访问: http://localhost:8080
```

## 在 Wukong 中使用 Longhorn

### 基本配置

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-longhorn
spec:
  cpu: 2
  memory: 4Gi
  
  disks:
    # 系统盘
    - name: system
      size: 20Gi
      storageClassName: longhorn  # 使用 Longhorn
      boot: true
      image: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"
    
    # 数据盘
    - name: data
      size: 100Gi
      storageClassName: longhorn
      boot: false
  
  cloudInitUser:
    name: ubuntu
    passwordHash: "$1$7.t8q8zZ$59I1IiMXy5w3gIl5Yrn/4/"
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: "/bin/bash"
  
  startStrategy:
    autoStart: true
```

### 生产环境配置

参考 `config/samples/vm_v1alpha1_wukong_production.yaml`:

```yaml
disks:
  # 系统盘：使用 Longhorn
  - name: system
    size: 30Gi
    storageClassName: longhorn
    boot: true
  
  # 数据盘：使用 Longhorn
  - name: data
    size: 200Gi
    storageClassName: longhorn
    boot: false
```

## 磁盘扩展

### 使用脚本扩展

```bash
# 扩展数据盘从 100Gi 到 200Gi
./scripts/expand-disk.sh ubuntu-longhorn data 200Gi
```

### 手动扩展

```bash
# 1. 编辑 Wukong 配置
kubectl edit wukong ubuntu-longhorn

# 2. 修改磁盘大小
# 例如：将 data 盘从 100Gi 改为 200Gi
#   - name: data
#     size: 200Gi  # 修改这里

# 3. Controller 会自动扩展 PVC

# 4. 在 VM 内部扩展文件系统
virtctl console ubuntu-longhorn-vm
# 然后执行:
sudo growpart /dev/vdb 1
sudo resize2fs /dev/vdb1
```

## Longhorn 管理

### 访问 Longhorn UI

```bash
# 端口转发
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# 访问 http://localhost:8080
```

在 UI 中可以：
- 查看所有卷的状态
- 创建快照
- 配置备份
- 监控存储使用情况

### 创建快照

```bash
# 使用 kubectl
kubectl create volumesnapshot <snapshot-name> \
  --source-pvc=<pvc-name> \
  --snapshot-class=longhorn-snapshot-class
```

### 配置备份

在 Longhorn UI 中：
1. 进入 Settings → Backup Target
2. 配置备份目标（S3、NFS 等）
3. 启用自动备份

## 故障排查

### 问题 1: Longhorn Pods 未就绪

```bash
# 检查 Pod 状态
kubectl get pods -n longhorn-system

# 查看 Pod 日志
kubectl logs -n longhorn-system <pod-name>

# 检查节点资源
kubectl describe node <node-name>
```

### 问题 2: PVC 无法绑定

```bash
# 检查 PVC 状态
kubectl get pvc
kubectl describe pvc <pvc-name>

# 检查 Longhorn 卷状态
kubectl get volumes.longhorn.io -n longhorn-system
```

### 问题 3: 卷扩展失败

```bash
# 检查 StorageClass 配置
kubectl get storageclass longhorn -o yaml

# 检查 PVC 状态
kubectl describe pvc <pvc-name>

# 检查 Longhorn 卷状态
kubectl get volumes.longhorn.io -n longhorn-system
```

## 性能优化

### 1. 配置副本数

在 Longhorn UI 中：
- Settings → General → Default Replica Count
- 建议：3 个副本（高可用）

### 2. 配置存储路径

在 Longhorn UI 中：
- Settings → General → Default Data Path
- 建议：使用 SSD 磁盘路径

### 3. 配置节点调度

```yaml
# 在 Wukong 中配置节点选择器
spec:
  highAvailability:
    nodeSelector:
      longhorn.io/node: "true"
```

## 最佳实践

### 1. 系统盘和数据盘分离

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 100Gi
    storageClassName: longhorn
    boot: false
```

### 2. 定期备份

- 在 Longhorn UI 中配置自动备份
- 定期创建快照
- 测试恢复流程

### 3. 监控存储使用

```bash
# 查看 PVC 使用情况
kubectl get pvc

# 在 VM 内部查看
virtctl console <vm-name>
df -h
```

### 4. 预留空间

在创建磁盘时预留一些空间，避免频繁扩展：

```yaml
disks:
  - name: data
    size: 150Gi  # 而不是 100Gi
    storageClassName: longhorn
```

## 迁移指南

### 从 local-path 迁移到 Longhorn

**步骤**:

1. **安装 Longhorn**
   ```bash
   ./scripts/setup-longhorn.sh
   ```

2. **创建新的 Wukong（使用 Longhorn）**
   ```yaml
   disks:
     - name: system
       size: 20Gi
       storageClassName: longhorn
       boot: true
   ```

3. **迁移数据**（在 VM 内部）
   ```bash
   # 在旧 VM 中备份数据
   tar -czf /tmp/backup.tar.gz /data
   
   # 在新 VM 中恢复数据
   tar -xzf /tmp/backup.tar.gz -C /
   ```

## 总结

| 特性 | Longhorn | local-path |
|------|----------|------------|
| 卷扩展 | ✅ | ❌ |
| 高可用 | ✅ | ❌ |
| 跨节点 | ✅ | ❌ |
| 快照 | ✅ | ❌ |
| 备份 | ✅ | ❌ |
| 资源占用 | 中等 | 低 |
| 适用场景 | 生产环境 | 开发测试 |

**关键点**:
- ✅ Longhorn 是 k3s 生产环境的理想选择
- ✅ 支持卷扩展，满足动态存储需求
- ✅ 提供高可用性和数据保护
- ✅ 易于管理和监控

## 下一步

1. **安装 Longhorn**: `./scripts/setup-longhorn.sh`
2. **创建测试 VM**: 使用 `config/samples/vm_v1alpha1_wukong_production.yaml`
3. **测试卷扩展**: `./scripts/expand-disk.sh`
4. **配置备份**: 在 Longhorn UI 中配置自动备份

