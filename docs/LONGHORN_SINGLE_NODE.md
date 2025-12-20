# Longhorn 单节点配置

## 单节点环境支持

✅ **Longhorn 可以在单节点环境下运行**，但需要特殊配置。

## 单节点配置

### 1. 配置副本数为 1

Longhorn 默认需要 3 个副本才能提供高可用性。在单节点环境下，需要将副本数设置为 1。

#### 方法 1: 通过 Longhorn UI（推荐）

```bash
# 访问 Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# 在浏览器中访问: http://localhost:8080
# 进入 Settings → General → Default Replica Count
# 设置为 1
```

#### 方法 2: 通过 kubectl

```bash
# 等待 Longhorn 完全就绪后
kubectl patch setting -n longhorn-system default-replica-count --type merge -p '{"value":"1"}'
```

### 2. 配置节点调度

确保节点可以调度 Longhorn 组件：

```bash
# 检查节点标签
kubectl get nodes --show-labels

# 如果需要，添加标签
kubectl label node <node-name> node.longhorn.io/create-default-disk=true
```

### 3. 配置存储路径

确保存储路径有足够的空间：

```bash
# 在节点上检查
df -h /var/lib/longhorn

# 如果需要，创建路径
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn
```

## 单节点限制

### ⚠️ 高可用性限制

- ❌ **无高可用性**: 单节点故障会导致所有数据不可用
- ❌ **无数据冗余**: 数据只有一份副本
- ❌ **无法迁移**: 无法在不同节点间迁移数据

### ✅ 适合场景

- ✅ **开发环境**: 开发和测试
- ✅ **边缘计算**: 单节点边缘环境
- ✅ **资源受限环境**: 资源有限的环境

### ⚠️ 不适合场景

- ❌ **生产环境（高可用要求）**: 需要多节点
- ❌ **关键业务**: 需要数据冗余
- ❌ **大规模部署**: 需要分布式存储

## 验证单节点配置

### 1. 检查副本数设置

```bash
kubectl get setting -n longhorn-system default-replica-count -o yaml
```

应该显示 `value: "1"`。

### 2. 创建测试 PVC

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-single-node-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 检查 PVC 状态
kubectl get pvc test-single-node-pvc

# 应该很快变为 Bound
```

### 3. 检查 Longhorn 卷

```bash
# 在 Longhorn UI 中查看卷
# 或使用 kubectl
kubectl get volumes.longhorn.io -n longhorn-system
```

## 单节点最佳实践

### 1. 定期备份

由于没有数据冗余，定期备份很重要：

```bash
# 在 Longhorn UI 中配置自动备份
# Settings → Backup Target
```

### 2. 监控存储使用

```bash
# 监控 PVC 使用情况
kubectl get pvc

# 在节点上监控磁盘空间
df -h /var/lib/longhorn
```

### 3. 预留空间

为 Longhorn 预留足够的磁盘空间：

```bash
# 建议至少预留 20% 的磁盘空间
# 例如：100GB 磁盘，至少预留 20GB
```

## 在 Wukong 中使用

单节点环境下，Wukong 可以正常使用 Longhorn：

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-single-node
spec:
  cpu: 2
  memory: 4Gi
  
  disks:
    - name: system
      size: 20Gi
      storageClassName: longhorn  # 单节点也可以使用
      boot: true
      image: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"
    
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

## 故障恢复

### 单节点故障

如果单节点故障：
- ❌ 所有数据会丢失（除非有备份）
- ❌ 无法自动恢复

### 备份和恢复

```bash
# 1. 定期备份（在 Longhorn UI 中配置）
# 2. 备份到外部存储（S3、NFS 等）
# 3. 节点故障后，从备份恢复
```

## 总结

| 特性 | 单节点 | 多节点 |
|------|--------|--------|
| 支持 | ✅ 是 | ✅ 是 |
| 需要配置 | ✅ 是（副本数=1） | ❌ 否 |
| 高可用 | ❌ 否 | ✅ 是 |
| 数据冗余 | ❌ 否 | ✅ 是 |
| 适合场景 | 开发/测试 | 生产环境 |

**关键点**:
- ✅ 单节点可以使用 Longhorn
- ✅ 需要配置副本数为 1
- ⚠️ 无高可用性和数据冗余
- ✅ 适合开发和测试环境

## 快速配置

```bash
# 1. 配置副本数为 1
kubectl patch setting -n longhorn-system default-replica-count --type merge -p '{"value":"1"}' 2>/dev/null || echo "等待 Longhorn 完全就绪后再执行"

# 2. 验证配置
kubectl get setting -n longhorn-system default-replica-count

# 3. 测试创建 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-single-node
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 4. 检查状态
kubectl get pvc test-single-node
```

