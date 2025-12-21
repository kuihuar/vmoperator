# 测试使用 Longhorn 创建虚拟机

## 快速测试

### 方法 1: 使用测试脚本（推荐）

```bash
./scripts/test-longhorn-vm.sh
```

脚本会自动：
1. 检查 Longhorn StorageClass
2. 检查 Wukong CRD
3. 检查 Controller
4. 创建测试 Wukong
5. 监控状态

### 方法 2: 手动创建

```bash
# 1. 创建测试 Wukong
kubectl apply -f config/samples/vm_v1alpha1_wukong_longhorn_test.yaml

# 2. 监控状态
kubectl get wukong ubuntu-longhorn-test -w

# 3. 检查相关资源
kubectl get vm,pvc,datavolume
```

## 测试配置

测试配置使用：
- **系统盘**: 10Gi，使用 Longhorn
- **数据盘**: 5Gi，使用 Longhorn（测试系统盘和数据盘分离）
- **镜像**: HTTP 源（`http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img`）

## 验证步骤

### 1. 检查 Wukong 状态

```bash
kubectl get wukong ubuntu-longhorn-test
kubectl describe wukong ubuntu-longhorn-test
```

### 2. 检查 PVC 状态

```bash
# 应该看到两个 PVC（系统盘和数据盘）
kubectl get pvc | grep ubuntu-longhorn-test

# 检查 PVC 详情
kubectl describe pvc ubuntu-longhorn-test-system
kubectl describe pvc ubuntu-longhorn-test-data
```

### 3. 检查 Longhorn 卷

```bash
# 在 Longhorn UI 中查看
# 或使用 kubectl
kubectl get volumes.longhorn.io -n longhorn-system | grep ubuntu-longhorn-test
```

### 4. 检查 VM 状态

```bash
kubectl get vm ubuntu-longhorn-test-vm
kubectl get vmi ubuntu-longhorn-test-vm
```

### 5. 检查 DataVolume（如果有）

```bash
kubectl get datavolume ubuntu-longhorn-test-system
kubectl describe datavolume ubuntu-longhorn-test-system
```

## 预期结果

### 成功的情况

1. **Wukong**: `Phase: Running`
2. **PVC**: `Status: Bound`
3. **VM**: `Status: Running`
4. **VMI**: `Status: Running`
5. **Longhorn 卷**: 在 Longhorn UI 中可见

### 可能的问题

#### 问题 1: PVC 无法绑定

**检查**:
```bash
kubectl describe pvc ubuntu-longhorn-test-system
```

**可能原因**:
- Longhorn 节点磁盘未配置
- 磁盘空间不足

**解决**:
- 在 Longhorn UI 中配置节点磁盘
- 或运行: `./scripts/fix-longhorn-disk-mismatch.sh`

#### 问题 2: DataVolume 导入失败

**检查**:
```bash
kubectl describe datavolume ubuntu-longhorn-test-system
kubectl logs -n cdi-system -l cdi.kubevirt.io=importer | grep ubuntu-longhorn-test
```

**可能原因**:
- HTTP 服务器不可访问
- 镜像文件不存在

**解决**:
- 确保 HTTP 服务器运行: `python3 -m http.server 8080 --directory /path/to/images`
- 检查镜像文件是否存在

#### 问题 3: VM 无法启动

**检查**:
```bash
kubectl describe vm ubuntu-longhorn-test-vm
kubectl describe vmi ubuntu-longhorn-test-vm
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

**可能原因**:
- 资源不足
- 调度问题
- KubeVirt 配置问题

## 验证 Longhorn 存储

### 在 Longhorn UI 中查看

1. 访问 Longhorn UI: `http://192.168.1.141:8088`
2. 进入 **Volumes** 页面
3. 应该看到两个卷：
   - `ubuntu-longhorn-test-system`
   - `ubuntu-longhorn-test-data`

### 检查卷状态

```bash
# 使用 kubectl
kubectl get volumes.longhorn.io -n longhorn-system

# 查看卷详情
kubectl get volumes.longhorn.io -n longhorn-system <volume-name> -o yaml
```

## 测试卷扩展

如果测试成功，可以测试卷扩展：

```bash
# 扩展数据盘从 5Gi 到 10Gi
./scripts/expand-disk.sh ubuntu-longhorn-test data 10Gi
```

## 清理测试资源

测试完成后，清理资源：

```bash
# 删除 Wukong（会自动删除相关资源）
kubectl delete wukong ubuntu-longhorn-test

# 或手动删除
kubectl delete vm ubuntu-longhorn-test-vm
kubectl delete pvc ubuntu-longhorn-test-system ubuntu-longhorn-test-data
kubectl delete datavolume ubuntu-longhorn-test-system 2>/dev/null || true
```

## 总结

| 步骤 | 命令 | 预期结果 |
|------|------|---------|
| 创建 Wukong | `kubectl apply -f config/samples/vm_v1alpha1_wukong_longhorn_test.yaml` | Wukong 创建成功 |
| 检查 PVC | `kubectl get pvc` | PVC 状态为 Bound |
| 检查 VM | `kubectl get vm` | VM 状态为 Running |
| 检查 Longhorn | Longhorn UI | 卷可见且正常 |

**关键点**:
- ✅ 即使 driver-deployer 卡住，Longhorn 仍然可用
- ✅ StorageClass 已存在，可以创建 PVC
- ✅ 可以测试系统盘和数据盘分离
- ✅ 可以测试卷扩展功能

