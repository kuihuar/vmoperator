# 修复 Longhorn Node 资源未创建问题

## 问题描述

```
Error from server (NotFound): nodes.longhorn.io "host1" not found
```

## 问题原因

Longhorn Manager 需要时间来发现 Kubernetes 节点并创建对应的 Longhorn Node 资源。这通常需要几分钟时间。

## 解决方案

### 方法 1: 等待 Node 资源创建（推荐）

使用等待脚本：

```bash
# 等待 Node 资源创建（最多 5 分钟）
./scripts/wait-for-longhorn-node.sh host1

# 或指定等待时间（秒）
./scripts/wait-for-longhorn-node.sh host1 600  # 等待 10 分钟
```

脚本会自动：
1. 检查 longhorn-manager 是否运行
2. 等待 Node 资源创建
3. 显示进度和诊断信息

### 方法 2: 手动等待

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 等待 Node 资源创建
for i in {1..60}; do
    if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
        echo "✓ Node 资源已创建"
        break
    fi
    echo "等待中... ($i/60)"
    sleep 5
done
```

### 方法 3: 检查并重启 Manager

如果等待很久仍未创建，可能是 Manager 的问题：

```bash
# 1. 检查 Manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 2. 查看 Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 3. 如果 Manager 有问题，重启它
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 4. 等待 Manager 重新启动
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# 5. 再次等待 Node 资源
./scripts/wait-for-longhorn-node.sh host1
```

## 验证 Node 资源

```bash
# 检查 Node 资源是否存在
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME"

# 查看 Node 资源详情
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml
```

## 常见问题

### 问题 1: Manager 未运行

**症状**: `kubectl get pods -n longhorn-system -l app=longhorn-manager` 返回空或 Pod 未运行

**解决**:
```bash
# 检查 Manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 查看日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 常见原因：缺少 open-iscsi
# 安装: sudo apt-get install -y open-iscsi
# 然后重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 2: Manager 运行但未创建 Node

**症状**: Manager Pod 运行正常，但 Node 资源未创建

**可能原因**:
1. Manager 需要更多时间
2. Manager 无法访问节点信息
3. RBAC 权限问题

**解决**:
```bash
# 1. 等待更长时间（10-15 分钟）
./scripts/wait-for-longhorn-node.sh host1 900

# 2. 检查 Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager | grep -i node

# 3. 重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 3: 节点名称不匹配

**症状**: 脚本使用的节点名称与实际节点名称不一致

**解决**:
```bash
# 检查实际的节点名称
kubectl get nodes

# 使用正确的节点名称
./scripts/wait-for-longhorn-node.sh <实际节点名称>
```

## 配置磁盘（Node 资源创建后）

Node 资源创建后，可以配置磁盘：

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 配置磁盘
./scripts/configure-longhorn-disk.sh /mnt/longhorn

# 或手动配置
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{
  "spec": {
    "disks": {
      "data-disk": {
        "allowScheduling": true,
        "evictionRequested": false,
        "path": "/mnt/longhorn",
        "storageReserved": 0,
        "tags": []
      }
    }
  }
}'
```

## 预防措施

1. **安装后等待**: 安装 Longhorn 后，等待 5-10 分钟让 Manager 完全初始化
2. **检查 Manager**: 确保所有 Manager Pods 都在运行
3. **使用等待脚本**: 使用 `wait-for-longhorn-node.sh` 自动等待

## 总结

| 问题 | 原因 | 解决 |
|------|------|------|
| Node 资源未创建 | Manager 需要时间发现节点 | 等待 5-10 分钟 |
| Manager 未运行 | 缺少依赖或配置问题 | 检查日志并修复 |
| 等待超时 | Manager 无法发现节点 | 重启 Manager 或检查权限 |

**推荐流程**:
1. 安装 Longhorn
2. 等待 Manager 就绪
3. 使用 `wait-for-longhorn-node.sh` 等待 Node 资源
4. 配置磁盘

## 参考

- 等待脚本: `./scripts/wait-for-longhorn-node.sh`
- 配置磁盘脚本: `./scripts/configure-longhorn-disk.sh`
- 重新安装脚本: `./scripts/reinstall-longhorn.sh`

