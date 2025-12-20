# Longhorn Backend API 等待逻辑

## Init Container 等待逻辑

Init Container `wait-longhorn-manager` 执行以下命令：

```bash
while [ $(curl -m 1 -s -o /dev/null -w "%{http_code}" http://longhorn-backend:9500/v1) != "200" ]; do 
  echo waiting; 
  sleep 2; 
done
```

### 解释

1. **每 2 秒检查一次**: `sleep 2`
2. **访问 API**: `http://longhorn-backend:9500/v1`
3. **检查 HTTP 状态码**: 期望返回 `200`
4. **如果返回 200**: Init Container 完成，主容器启动
5. **如果未返回 200**: 继续等待，输出 "waiting"

## 它在等待什么？

Init Container 在等待 **Longhorn Backend API** 就绪，这个 API 由 `longhorn-manager` Pod 提供。

### 依赖链

```
longhorn-driver-deployer (Init Container)
  └─> 等待 longhorn-backend Service
        └─> 等待 longhorn-manager Pod
              └─> 等待 manager 启动并监听 9500 端口
                    └─> 等待 manager 健康检查通过
```

## 诊断步骤

### 1. 检查 longhorn-backend Service

```bash
# 检查 Service 是否存在
kubectl get svc -n longhorn-system longhorn-backend

# 检查 Service 的 Endpoints
kubectl get endpoints -n longhorn-system longhorn-backend
```

**如果 Endpoints 为空**，说明没有 `longhorn-manager` Pod 在运行。

### 2. 检查 longhorn-manager Pods

```bash
# 检查 manager Pods 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 查看 manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50
```

### 3. 测试 API 访问

```bash
# 从 manager Pod 内部测试
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://localhost:9500/v1
```

### 4. 使用诊断脚本

```bash
./scripts/check-longhorn-backend.sh
```

## 常见问题

### 问题 1: Service 没有 Endpoints

**症状**:
```bash
kubectl get endpoints -n longhorn-system longhorn-backend
# NAME                ENDPOINTS   AGE
# longhorn-backend   <none>      10m
```

**原因**: `longhorn-manager` Pod 未运行或未就绪。

**解决**:
1. 检查 manager Pod 状态
2. 修复 manager（通常是 iscsi 问题）
3. 等待 manager 就绪

### 问题 2: Manager Pod 是 CrashLoopBackOff

**症状**:
```
longhorn-manager-xxx   0/1     CrashLoopBackOff
```

**原因**: 通常是缺少 `open-iscsi`。

**解决**:
```bash
# 在所有节点上安装 open-iscsi
sudo apt-get update && sudo apt-get install -y open-iscsi
sudo systemctl enable iscsid && sudo systemctl start iscsid

# 重启 manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 3: Manager Pod 运行但 API 不可访问

**症状**: Manager 是 `Running`，但 API 返回非 200。

**检查**:
```bash
# 检查 manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 检查 manager 是否监听 9500 端口
kubectl exec -n longhorn-system <manager-pod> -- netstat -tlnp | grep 9500
```

## 解决方案

### 如果 manager 未就绪

1. **检查 manager 状态**:
   ```bash
   kubectl get pods -n longhorn-system -l app=longhorn-manager
   ```

2. **查看 manager 日志**:
   ```bash
   kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50
   ```

3. **修复 manager**（通常是 iscsi 问题）:
   ```bash
   # 在节点上安装 open-iscsi
   sudo apt-get update && sudo apt-get install -y open-iscsi
   sudo systemctl enable iscsid && sudo systemctl start iscsid
   ```

4. **重启 manager**:
   ```bash
   kubectl delete pod -n longhorn-system -l app=longhorn-manager
   ```

5. **等待 manager 就绪**:
   ```bash
   kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
   ```

### 如果 manager 已就绪但 driver-deployer 仍卡住

如果 manager 已经是 `Running` 且 `1/1 Ready`，但 driver-deployer 仍然卡住超过 5 分钟：

```bash
# 重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

## 验证

修复后，验证：

```bash
# 1. 检查 manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager
# 应该看到: Running   1/1

# 2. 检查 Service Endpoints
kubectl get endpoints -n longhorn-system longhorn-backend
# 应该看到有 IP 地址

# 3. 测试 API
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://localhost:9500/v1 | head -5
# 应该返回 JSON 数据

# 4. 检查 driver-deployer
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer
# 应该看到: Running   1/1
```

## 总结

| 组件 | 状态 | 说明 |
|------|------|------|
| longhorn-manager | Running 1/1 | Manager 已就绪，API 可用 |
| longhorn-backend Service | 有 Endpoints | Service 指向 manager Pod |
| wait-longhorn-manager Init | 完成 | API 返回 200，Init Container 完成 |
| longhorn-driver-deployer | Running 1/1 | 主容器启动，部署完成 |

**关键点**:
- ✅ Init Container 等待 `http://longhorn-backend:9500/v1` 返回 200
- ✅ 这个 API 由 `longhorn-manager` 提供
- ✅ 必须先确保 `longhorn-manager` 正常运行
- ✅ Manager 就绪后，Init Container 会自动完成

