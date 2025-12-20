# 镜像推送成功后的下一步操作

## ✅ 当前状态

- ✅ 镜像已构建: `novasphere/ubuntu-noble:latest`
- ✅ 镜像已推送到本地 registry: `host.docker.internal:5000/ubuntu-noble:latest`
- ✅ Registry 运行正常

## 🎯 下一步：创建 Wukong 资源

### 步骤 1: 创建 Wukong 资源

使用已准备好的示例文件：

```bash
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

或者手动创建：

```bash
cat <<EOF | kubectl apply -f -
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-local
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 30Gi
      storageClassName: docker-desktop
      boot: true
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
  startStrategy:
    autoStart: true
EOF
```

### 步骤 2: 监控资源创建过程

#### 2.1 查看 Wukong 状态

```bash
# 查看 Wukong 资源
kubectl get wukong ubuntu-noble-local

# 查看详细信息
kubectl describe wukong ubuntu-noble-local

# 实时监控（按 Ctrl+C 退出）
kubectl get wukong ubuntu-noble-local -w
```

#### 2.2 查看 DataVolume 状态（CDI 正在导入镜像）

```bash
# 查看 DataVolume
kubectl get datavolume

# 查看详细信息
kubectl describe datavolume ubuntu-noble-local-system

# 实时监控
kubectl get datavolume -w
```

**DataVolume 状态说明**:
- `Pending`: 等待处理
- `ImportScheduled`: 导入任务已调度
- `ImportInProgress`: 正在导入镜像（可能需要几分钟）
- `Succeeded`: 导入成功 ✅
- `Failed`: 导入失败 ❌

#### 2.3 查看 Importer Pod 日志

```bash
# 查找 Importer Pod
kubectl get pods | grep importer

# 查看日志（替换 <pod-name> 为实际 Pod 名称）
kubectl logs <importer-pod-name> -f
```

#### 2.4 查看 PVC 状态

```bash
# 查看 PVC
kubectl get pvc

# 查看详细信息
kubectl describe pvc ubuntu-noble-local-system
```

**PVC 状态说明**:
- `Pending`: 等待绑定
- `Bound`: 已绑定 ✅

### 步骤 3: 监控 VirtualMachine 创建

```bash
# 查看 VirtualMachine
kubectl get vm

# 查看详细信息
kubectl describe vm ubuntu-noble-local-vm

# 查看 VirtualMachineInstance（运行中的 VM）
kubectl get vmi

# 实时监控
kubectl get vm -w
kubectl get vmi -w
```

### 步骤 4: 验证 VM 运行状态

```bash
# 查看 Wukong 最终状态
kubectl get wukong ubuntu-noble-local -o yaml

# 查看 VM 状态
kubectl get vm ubuntu-noble-local-vm -o yaml

# 查看 VMI 状态（如果已启动）
kubectl get vmi ubuntu-noble-local-vm -o yaml
```

## 📊 完整监控命令

创建一个监控脚本，同时查看所有相关资源：

```bash
# 在一个终端窗口中运行
watch -n 2 'echo "=== Wukong ===" && kubectl get wukong && echo "" && echo "=== DataVolume ===" && kubectl get datavolume && echo "" && echo "=== PVC ===" && kubectl get pvc && echo "" && echo "=== VM ===" && kubectl get vm && echo "" && echo "=== VMI ===" && kubectl get vmi'
```

或者分别查看：

```bash
# 查看所有相关资源
echo "=== Wukong ==="
kubectl get wukong

echo ""
echo "=== DataVolume ==="
kubectl get datavolume

echo ""
echo "=== PVC ==="
kubectl get pvc

echo ""
echo "=== VM ==="
kubectl get vm

echo ""
echo "=== VMI ==="
kubectl get vmi

echo ""
echo "=== Importer Pods ==="
kubectl get pods | grep importer
```

## ⏱️ 预期时间线

### 正常流程时间线

```
0 分钟: 创建 Wukong 资源
  ↓
1 分钟: DataVolume 创建，Importer Pod 启动
  ↓
2-5 分钟: CDI 正在从 registry 拉取镜像（取决于镜像大小）
  ↓
5-10 分钟: 镜像导入完成，PVC 绑定
  ↓
10-15 分钟: VirtualMachine 创建，VMI 启动
  ↓
15+ 分钟: VM 运行中 ✅
```

### 镜像大小参考

- **小镜像 (< 1GB)**: 2-5 分钟
- **中等镜像 (1-5GB)**: 5-15 分钟
- **大镜像 (> 5GB)**: 15-30 分钟或更长

## 🐛 故障排查

### 问题 1: DataVolume 一直处于 Pending

**检查**:
```bash
kubectl describe datavolume ubuntu-noble-local-system
kubectl get events --sort-by=.metadata.creationTimestamp
```

**可能原因**:
- CDI 未安装或未运行
- 资源配额不足
- StorageClass 不存在

**解决**:
```bash
# 检查 CDI
kubectl get pods -n cdi

# 检查 StorageClass
kubectl get storageclass
```

### 问题 2: DataVolume 导入失败

**检查**:
```bash
# 查看 DataVolume 事件
kubectl describe datavolume ubuntu-noble-local-system

# 查看 Importer Pod 日志
kubectl logs <importer-pod-name>
```

**可能原因**:
- 无法访问 registry
- 镜像不存在
- 网络问题

**解决**:
```bash
# 测试从 Kubernetes Pod 访问 registry
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl http://host.docker.internal:5000/v2/_catalog

# 验证镜像存在
curl http://localhost:5000/v2/_catalog
```

### 问题 3: PVC 无法绑定

**检查**:
```bash
kubectl describe pvc ubuntu-noble-local-system
kubectl get storageclass
```

**可能原因**:
- StorageClass 不存在
- 存储空间不足
- 存储驱动问题

**解决**:
```bash
# 检查 StorageClass
kubectl get storageclass

# 如果 docker-desktop 不存在，使用其他 StorageClass
# 修改 Wukong 配置中的 storageClassName
```

### 问题 4: VM 无法启动

**检查**:
```bash
kubectl describe vm ubuntu-noble-local-vm
kubectl describe vmi ubuntu-noble-local-vm
kubectl get events --sort-by=.metadata.creationTimestamp
```

**可能原因**:
- 镜像格式问题
- 资源不足
- 网络配置问题

## ✅ 成功标志

当看到以下状态时，说明一切正常：

```bash
# Wukong
NAME                 PHASE     READY
ubuntu-noble-local   Running   True

# DataVolume
NAME                        PHASE       PROGRESS
ubuntu-noble-local-system   Succeeded   100.0%

# PVC
NAME                        STATUS   VOLUME
ubuntu-noble-local-system   Bound    pvc-xxx

# VM
NAME                    AGE   STATUS    READY
ubuntu-noble-local-vm   10m   Running   True

# VMI
NAME                    AGE     PHASE     IP            NODENAME
ubuntu-noble-local-vm   10m     Running   10.244.x.x    docker-desktop
```

## 🎉 下一步操作

VM 成功运行后，你可以：

1. **查看 VM 控制台**:
   ```bash
   # 需要安装 virtctl
   virtctl console ubuntu-noble-local-vm
   ```

2. **SSH 到 VM**（如果配置了 SSH）:
   ```bash
   # 获取 VM IP
   kubectl get vmi ubuntu-noble-local-vm -o jsonpath='{.status.interfaces[0].ipAddress}'
   
   # SSH（需要配置 SSH 密钥）
   ssh user@<vm-ip>
   ```

3. **查看 VM 日志**:
   ```bash
   kubectl logs -f <vmi-pod-name>
   ```

4. **删除测试资源**（如果需要）:
   ```bash
   kubectl delete wukong ubuntu-noble-local
   ```

## 📚 相关文档

- [Wukong API 文档](./API.md)
- [CDI 指南](./CDI_GUIDE.md)
- [故障排查指南](./DEVELOPMENT.md#故障排查)

---

**提示**: 如果遇到问题，先查看 DataVolume 和 Importer Pod 的日志，通常能找到原因。

