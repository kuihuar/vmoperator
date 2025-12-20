# Longhorn 故障排查指南

## 常见问题

### 问题 1: longhorn-manager CrashLoopBackOff

**症状**:
```
longhorn-manager-xxx   0/1     CrashLoopBackOff   6
```

**常见错误**:
```
Error starting manager: Failed environment check, please make sure you have iscsiadm/open-iscsi installed on the host
```

**可能原因**:
1. **缺少 open-iscsi**（最常见）⭐
2. 节点资源不足（CPU/内存）
3. 存储路径配置问题
4. 节点标签缺失
5. 权限问题

**解决方案**:

#### 0. 安装 open-iscsi（最常见的问题）⭐

**如果错误信息包含 `iscsiadm` 或 `open-iscsi`**，这是最常见的问题：

**Ubuntu/Debian**:
```bash
# SSH 到节点
ssh <node-ip>

# 安装 open-iscsi
sudo apt-get update
sudo apt-get install -y open-iscsi

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

**CentOS/RHEL**:
```bash
# SSH 到节点
ssh <node-ip>

# 安装 iscsi-initiator-utils
sudo yum install -y iscsi-initiator-utils

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

**使用安装脚本**:
```bash
# 在节点上运行
./scripts/install-open-iscsi.sh
```

**在所有节点上安装后，重启 longhorn-manager**:
```bash
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

#### 1. 检查日志

```bash
# 获取 Pod 名称
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')

# 查看日志
kubectl logs -n longhorn-system $MANAGER_POD --tail=100

# 查看 Pod 详情
kubectl describe pod -n longhorn-system $MANAGER_POD
```

#### 2. 检查节点资源

```bash
# 检查节点资源
kubectl top nodes  # 需要 metrics-server

# 或查看节点详情
kubectl describe nodes
```

**如果资源不足**:
- 增加节点资源
- 或减少其他工作负载

#### 3. 检查存储路径

Longhorn 需要在节点上有可写的存储路径。

```bash
# 检查 Longhorn 配置
kubectl get setting -n longhorn-system default-data-path -o yaml

# 默认路径通常是: /var/lib/longhorn
```

**在节点上检查**:
```bash
# SSH 到节点
ssh <node-ip>

# 检查磁盘空间
df -h

# 检查路径权限
ls -la /var/lib/longhorn
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn
```

#### 4. 检查节点标签

Longhorn 可能需要特定的节点标签。

```bash
# 查看节点标签
kubectl get nodes --show-labels

# 如果需要，添加标签
kubectl label node <node-name> node.longhorn.io/create-default-disk=true
```

#### 5. 重新部署

如果以上都正常，尝试重新部署：

```bash
# 删除有问题的 Pod（会自动重建）
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 或重新安装 Longhorn
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
# 等待清理完成
sleep 30
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

### 问题 2: longhorn-driver-deployer Init:0/1

**症状**:
```
longhorn-driver-deployer-xxx   0/1     Init:0/1
```

**查看 Init Container 日志**:
```bash
kubectl logs -n longhorn-system <pod-name> -c wait-longhorn-manager
```

**原因**: Init Container `wait-longhorn-manager` 在等待 `longhorn-manager` 就绪。

**解决方案**:

#### 1. 先修复 longhorn-manager（必需）

`driver-deployer` 依赖于 `longhorn-manager`，必须先修复 Manager：

```bash
# 检查 manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 如果 manager 是 CrashLoopBackOff，先修复（通常是缺少 open-iscsi）
# 见问题 1 的解决方案
```

#### 2. 等待 Manager 就绪

```bash
# 等待 manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```

#### 3. 重启 driver-deployer（可选）

如果 Manager 已就绪但 driver-deployer 仍然卡住：

```bash
# 删除 driver-deployer Pod（会自动重建）
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer

# 等待重建
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -w
```

#### 4. 检查 Init Container 日志

```bash
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')

# 查看 Init Container 日志
kubectl logs -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager
```

**关键点**: `driver-deployer` 会一直等待直到 `longhorn-manager` 就绪，这是正常行为。

### 问题 3: 节点磁盘空间不足

**检查**:
```bash
# 在节点上
df -h
```

**解决**:
- 清理不需要的文件
- 扩展磁盘
- 或配置 Longhorn 使用其他路径

### 问题 4: 单节点环境

**问题**: Longhorn 需要至少 3 个副本才能提供高可用性，单节点环境可能有问题。

**解决方案**:

#### 选项 1: 配置单节点模式

```bash
# 创建 Setting
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: default-replica-count
  namespace: longhorn-system
value: "1"
EOF
```

#### 选项 2: 使用 local-path（开发环境）

对于单节点开发环境，可以考虑使用 `local-path`：

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: local-path  # 使用 local-path
    boot: true
```

### 问题 5: 网络问题

**检查**:
```bash
# 检查 Pod 网络
kubectl get pods -n longhorn-system -o wide

# 检查 Service
kubectl get svc -n longhorn-system
```

**解决**:
- 检查 CNI 配置
- 检查防火墙规则
- 检查节点网络连接

## 诊断步骤

### 1. 运行诊断脚本

```bash
./scripts/diagnose-longhorn.sh
```

### 2. 检查关键日志

```bash
# Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100

# Driver Deployer 日志
kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --tail=100

# 所有 Pod 事件
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | tail -30
```

### 3. 检查资源状态

```bash
# 节点资源
kubectl describe nodes

# Pod 资源请求
kubectl describe pods -n longhorn-system | grep -A 5 "Requests:"
```

## 快速修复

### 方法 1: 重新安装

```bash
# 1. 删除 Longhorn
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 2. 等待清理（约 1-2 分钟）
kubectl wait --for=delete namespace/longhorn-system --timeout=120s 2>/dev/null || true

# 3. 重新安装
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 4. 等待就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s
```

### 方法 2: 修复节点配置

```bash
# 在节点上执行
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn

# 检查磁盘空间
df -h /var/lib/longhorn
```

### 方法 3: 配置单节点模式

```bash
# 等待 Manager 就绪后
kubectl patch setting -n longhorn-system default-replica-count --type merge -p '{"value":"1"}'
```

## 验证修复

```bash
# 检查 Pod 状态
kubectl get pods -n longhorn-system

# 应该看到所有 Pod 都是 Running
# longhorn-manager-xxx   1/1     Running
# longhorn-driver-deployer-xxx   1/1     Running
# longhorn-ui-xxx   1/1     Running

# 检查 StorageClass
kubectl get storageclass longhorn
```

## 获取帮助

如果问题仍然存在：

1. **查看 Longhorn 官方文档**: https://longhorn.io/docs/
2. **查看 GitHub Issues**: https://github.com/longhorn/longhorn/issues
3. **收集诊断信息**:
   ```bash
   # 运行诊断脚本
   ./scripts/diagnose-longhorn.sh > longhorn-diagnosis.txt
   
   # 收集日志
   kubectl logs -n longhorn-system -l app=longhorn-manager > longhorn-manager.log
   ```

## 临时解决方案

如果 Longhorn 无法正常工作，可以临时使用 `local-path`：

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: local-path  # 临时使用 local-path
    boot: true
```

**注意**: `local-path` 不支持卷扩展，仅用于开发测试。

