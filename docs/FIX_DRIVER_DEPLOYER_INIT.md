# 修复 longhorn-driver-deployer Init:0/1 问题

## 问题描述

`longhorn-driver-deployer` Pod 一直卡在 `Init:0/1` 状态，无法完成初始化。

## 问题原因

`driver-deployer` 的 Init Container 在等待 `longhorn-backend` API 返回 HTTP 200。常见原因：

1. **longhorn-backend Service 没有 Endpoints**（最常见）
   - Manager Pod 未运行
   - Manager Pod 未就绪
   - Manager 无法绑定 9500 端口

2. **网络连接问题**
   - Pod 无法访问 Service
   - DNS 解析失败
   - 防火墙规则阻止

3. **Manager API 未就绪**
   - Manager 刚启动，需要更多时间
   - Manager 配置问题

## 诊断步骤

### 方法 1: 使用深度诊断脚本（推荐）

```bash
# 自动诊断
./scripts/deep-diagnose-driver-deployer.sh

# 或指定 Pod 名称
./scripts/deep-diagnose-driver-deployer.sh longhorn-driver-deployer-5bb579d858-jpst5
```

### 方法 2: 手动诊断

#### 步骤 1: 检查 driver-deployer 状态

```bash
# 查看 Pod 状态
kubectl get pod -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5

# 查看详细状态
kubectl describe pod -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5
```

#### 步骤 2: 查看 Init Container 日志

```bash
# 查看所有 Init Container 日志
kubectl logs -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5 --all-containers=true

# 查看特定 Init Container 日志
kubectl logs -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5 -c wait-for-backend
```

#### 步骤 3: 检查 longhorn-backend Service

```bash
# 检查 Service
kubectl get svc -n longhorn-system longhorn-backend

# 检查 Endpoints
kubectl get endpoints -n longhorn-system longhorn-backend
```

**关键检查**:
- 如果 Endpoints 为空 → Manager Pod 未运行或未就绪
- 如果 Endpoints 有值 → 继续检查网络连接

#### 步骤 4: 检查 Manager Pods

```bash
# 检查 Manager Pods
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 查看 Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50
```

#### 步骤 5: 从 Pod 内测试连接

```bash
# 测试 DNS 解析
kubectl exec -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5 -c wait-for-backend -- nslookup longhorn-backend

# 测试 HTTP 连接
kubectl exec -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5 -c wait-for-backend -- wget -qO- --timeout=5 "http://longhorn-backend:9500/v1"
```

## 解决方案

### 方案 1: 等待 Manager 就绪（如果 Manager 刚启动）

```bash
# 等待 Manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 等待 Endpoints 创建
for i in {1..60}; do
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [ -n "$ENDPOINTS" ]; then
        echo "✓ Endpoints 已创建"
        break
    fi
    echo "等待中... ($i/60)"
    sleep 2
done

# 然后重启 driver-deployer
kubectl delete pod -n longhorn-system longhorn-driver-deployer-5bb579d858-jpst5
```

### 方案 2: 修复 Manager 问题（如果 Manager 未运行）

```bash
# 1. 检查 Manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 2. 查看 Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 3. 常见问题：缺少 open-iscsi
# 安装: sudo apt-get install -y open-iscsi
# 启动: sudo systemctl enable iscsid && sudo systemctl start iscsid

# 4. 重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 5. 等待 Manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 6. 重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

### 方案 3: 使用修复脚本（推荐）

```bash
# 自动修复
./scripts/fix-driver-deployer-init.sh
```

脚本会自动：
1. 检查 longhorn-backend Service 和 Endpoints
2. 检查 Manager Pods 状态
3. 等待 Endpoints 创建（如果需要）
4. 重启 driver-deployer
5. 监控新 Pod 状态

### 方案 4: 在节点上直接检查（SSH 到节点）

如果可以通过 SSH 访问节点（如 `ssh jianfen@192.168.1.141`），可以：

```bash
# 1. SSH 到节点
ssh jianfen@192.168.1.141

# 2. 检查 Manager Pod 是否监听 9500 端口
# 找到 Manager Pod 的容器
sudo crictl ps | grep longhorn-manager

# 3. 进入容器检查
CONTAINER_ID=$(sudo crictl ps | grep longhorn-manager | awk '{print $1}' | head -1)
sudo crictl exec $CONTAINER_ID netstat -tlnp | grep 9500
# 或
sudo crictl exec $CONTAINER_ID ss -tlnp | grep 9500

# 4. 检查 Manager 日志
sudo crictl logs $CONTAINER_ID --tail=50 | grep -iE "listen|9500|error"
```

## 验证修复

修复后，验证：

```bash
# 1. 检查 driver-deployer 状态
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer

# 应该看到状态为 Succeeded

# 2. 检查 CSI Driver
kubectl get csidriver driver.longhorn.io

# 应该看到 CSI Driver 已创建

# 3. 检查 CSI 组件
kubectl get pods -n longhorn-system | grep csi

# 应该看到 CSI 组件运行
```

## 常见问题排查

### 问题 1: Manager Pod CrashLoopBackOff

**症状**: Manager Pod 一直重启

**原因**: 通常缺少 `open-iscsi`

**解决**:
```bash
# 在节点上安装
sudo apt-get install -y open-iscsi
sudo systemctl enable iscsid
sudo systemctl start iscsid

# 重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 2: Manager 运行但无 Endpoints

**症状**: Manager Pod 运行，但 Endpoints 为空

**原因**: Manager 无法绑定 9500 端口或需要更多时间

**解决**:
```bash
# 1. 检查 Manager 是否监听 9500
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- netstat -tlnp | grep 9500

# 2. 查看 Manager 日志
kubectl logs -n longhorn-system $MANAGER_POD --tail=50

# 3. 等待更长时间（10-15 分钟）
# 4. 如果仍无 Endpoints，重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 3: 网络连接失败

**症状**: Endpoints 存在，但 Pod 无法连接

**解决**:
```bash
# 1. 检查 DNS
kubectl exec -n longhorn-system <driver-deployer-pod> -c wait-for-backend -- nslookup longhorn-backend

# 2. 检查网络策略
kubectl get networkpolicies -n longhorn-system

# 3. 检查防火墙（在节点上）
sudo iptables -L -n | grep -E "9500|longhorn"
```

## 快速修复命令

```bash
# 一键修复
./scripts/fix-driver-deployer-init.sh

# 或手动修复
# 1. 确保 Manager 运行
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 2. 等待 Endpoints
kubectl get endpoints -n longhorn-system longhorn-backend

# 3. 重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

## 在节点上排查（SSH 访问）

如果可以通过 SSH 访问节点：

```bash
# SSH 到节点
ssh jianfen@192.168.1.141

# 检查 k3s 服务
sudo systemctl status k3s

# 检查网络接口
sudo ip addr show flannel.1
sudo ip addr show cni0

# 检查 Manager 容器
sudo crictl ps | grep longhorn-manager

# 查看 Manager 日志
MANAGER_CONTAINER=$(sudo crictl ps | grep longhorn-manager | awk '{print $1}' | head -1)
sudo crictl logs $MANAGER_CONTAINER --tail=50

# 检查端口监听
sudo crictl exec $MANAGER_CONTAINER netstat -tlnp | grep 9500
```

## 总结

| 问题 | 原因 | 解决 |
|------|------|------|
| Endpoints 为空 | Manager 未运行 | 修复 Manager 并重启 |
| Endpoints 为空 | Manager 刚启动 | 等待 5-10 分钟 |
| 网络连接失败 | DNS/防火墙问题 | 检查网络配置 |
| Init 一直等待 | API 未就绪 | 等待或重启 driver-deployer |

**推荐流程**:
1. 运行诊断脚本: `./scripts/deep-diagnose-driver-deployer.sh`
2. 根据诊断结果修复问题
3. 运行修复脚本: `./scripts/fix-driver-deployer-init.sh`
4. 验证修复结果

## 参考

- 深度诊断脚本: `./scripts/deep-diagnose-driver-deployer.sh`
- 修复脚本: `./scripts/fix-driver-deployer-init.sh`
- 网络诊断: `./scripts/check-k3s-network.sh`

