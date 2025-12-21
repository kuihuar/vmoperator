#!/bin/bash

# 诊断 PVC Pending 问题

echo "=== 诊断 PVC Pending 问题 ==="
echo ""

PVC_NAME="${1:-ubuntu-longhorn-test-system}"

if [ -z "$PVC_NAME" ]; then
    echo "用法: $0 <pvc-name>"
    echo "示例: $0 ubuntu-longhorn-test-system"
    exit 1
fi

echo "PVC: $PVC_NAME"
echo ""

# 1. 检查 PVC 状态
echo "1. 检查 PVC 状态..."
kubectl get pvc "$PVC_NAME" -o wide
echo ""

# 2. 查看 PVC 详情
echo "2. PVC 详情:"
kubectl describe pvc "$PVC_NAME" | grep -A 30 "Events:" | head -35
echo ""

# 3. 检查 StorageClass
echo "3. 检查 StorageClass..."
STORAGE_CLASS=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
echo "StorageClass: $STORAGE_CLASS"

if [ "$STORAGE_CLASS" = "longhorn" ]; then
    echo "检查 longhorn StorageClass..."
    kubectl get storageclass longhorn -o yaml | grep -A 5 "provisioner\|parameters"
    echo ""
    
    # 检查 provisioner
    PROVISIONER=$(kubectl get storageclass longhorn -o jsonpath='{.provisioner}' 2>/dev/null)
    echo "Provisioner: $PROVISIONER"
    
    # 检查 CSI Driver
    if kubectl get csidriver "$PROVISIONER" &>/dev/null; then
        echo "✓ CSI Driver 存在"
    else
        echo "⚠️  CSI Driver 不存在: $PROVISIONER"
    fi
else
    echo "⚠️  StorageClass 不是 longhorn"
fi
echo ""

# 4. 检查 Longhorn Node
echo "4. 检查 Longhorn Node..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "节点名称: $NODE_NAME"

if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "Longhorn Node 资源存在"
    echo ""
    echo "Node 状态:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.conditions[*]}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 10 "conditions:" | head -15
    echo ""
    
    echo "Node 磁盘配置:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 20 "disks:" | head -25
    echo ""
    
    # 检查是否有磁盘
    DISK_COUNT=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null | grep -o "path" | wc -l | tr -d ' ')
    if [ "$DISK_COUNT" -gt 0 ]; then
        echo "✓ Node 有磁盘配置 ($DISK_COUNT 个)"
    else
        echo "❌ Node 没有磁盘配置（这是问题所在！）"
        echo ""
        echo "需要配置磁盘:"
        echo "  1. 在 Longhorn UI 中: Nodes → $NODE_NAME → Disks → Add Disk"
        echo "  2. 或运行: ./scripts/fix-longhorn-disk-mismatch.sh"
    fi
else
    echo "❌ Longhorn Node 资源不存在"
    echo "等待 Longhorn 创建 Node 资源..."
fi
echo ""

# 5. 检查 Longhorn Manager
echo "5. 检查 Longhorn Manager..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Manager Pod: $MANAGER_POD"
    echo "状态: $MANAGER_STATUS"
    
    if [ "$MANAGER_STATUS" != "Running" ]; then
        echo "⚠️  Manager 未运行，查看日志:"
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=20 2>&1 | tail -10
    fi
else
    echo "❌ Manager Pod 不存在"
fi
echo ""

# 6. 检查存储空间
echo "6. 检查存储空间..."
echo "（需要在节点上检查: df -h /var/lib/longhorn）"
echo ""

# 7. 检查事件
echo "7. 检查相关事件..."
kubectl get events --field-selector involvedObject.name=$PVC_NAME --sort-by='.lastTimestamp' | tail -10
echo ""

# 8. 提供解决方案
echo "8. 解决方案:"
echo ""

# 检查 Node 是否有磁盘配置
if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    DISK_COUNT=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null | grep -o "path" | wc -l | tr -d ' ')
    if [ "$DISK_COUNT" -eq 0 ]; then
        echo "❌ 问题: Longhorn Node 没有磁盘配置"
        echo ""
        echo "解决方案 1: 通过 Longhorn UI 配置（推荐）"
        echo "  1. 访问 Longhorn UI: kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
        echo "  2. 进入 Nodes → $NODE_NAME → Disks"
        echo "  3. 点击 Add Disk"
        echo "  4. 配置路径: /var/lib/longhorn"
        echo "  5. 保存"
        echo ""
        echo "解决方案 2: 使用脚本修复"
        echo "  ./scripts/fix-longhorn-disk-mismatch.sh"
        echo ""
        echo "解决方案 3: 手动配置"
        echo "  kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME"
        echo "  添加 disks 配置"
    else
        echo "✓ Node 有磁盘配置"
        echo ""
        echo "如果 PVC 仍然 Pending，可能原因:"
        echo "  1. 存储空间不足"
        echo "  2. Longhorn 节点未就绪"
        echo "  3. 网络问题"
        echo ""
        echo "检查:"
        echo "  - 节点磁盘空间: df -h /var/lib/longhorn"
        echo "  - Node 状态: kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME"
    fi
else
    echo "⚠️  Longhorn Node 资源不存在，等待创建..."
fi

echo ""
echo "=== 完成 ==="

