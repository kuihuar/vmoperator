#!/bin/bash

# 修复 Longhorn 磁盘配置不一致问题

set -e

echo "=== 修复 Longhorn 磁盘配置不一致 ==="
echo ""

# 1. 检查错误
echo "1. 检查 Manager 日志中的磁盘错误..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    echo "Manager Pod: $MANAGER_POD"
    echo ""
    echo "查找磁盘相关错误:"
    kubectl logs -n longhorn-system "$MANAGER_POD" --tail=200 2>&1 | grep -i "mismatching\|disk\|node" | tail -10
    echo ""
fi

# 2. 检查 Longhorn Node 资源
echo "2. 检查 Longhorn Node 资源..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "节点名称: $NODE_NAME"
echo ""

if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "Longhorn Node 资源存在"
    echo ""
    echo "Node 磁盘配置:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 20 "disks:" | head -25
    echo ""
    
    echo "Node 状态:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.conditions[*]}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 10 "conditions:" | head -15
else
    echo "⚠️  Longhorn Node 资源不存在（可能需要等待创建）"
fi
echo ""

# 3. 检查节点上的实际磁盘
echo "3. 检查节点上的实际磁盘（需要在节点上执行）..."
echo "请在节点上执行以下命令:"
echo "  df -h"
echo "  lsblk"
echo "  ls -la /var/lib/longhorn"
echo ""

# 4. 提供修复方案
echo "4. 修复方案:"
echo ""

echo "方案 1: 清理并重新初始化 Node 磁盘配置"
echo "  1. 删除 Longhorn Node 资源（会自动重建）"
echo "     kubectl delete nodes.longhorn.io -n longhorn-system $NODE_NAME"
echo ""
echo "  2. 等待 Node 资源重建"
echo "     kubectl wait --for=condition=ready nodes.longhorn.io/$NODE_NAME -n longhorn-system --timeout=300s"
echo ""

echo "方案 2: 手动配置磁盘（通过 Longhorn UI）"
echo "  1. 访问 Longhorn UI:"
echo "     kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo "  2. 进入 Nodes → $NODE_NAME → Disks"
echo "  3. 配置磁盘路径（例如: /var/lib/longhorn）"
echo ""

echo "方案 3: 通过 kubectl 配置"
echo "  1. 编辑 Node 资源:"
echo "     kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME"
echo "  2. 配置 disks 字段，指定磁盘路径"
echo ""

# 5. 自动修复（如果可能）
read -p "是否尝试自动修复（删除并重建 Node 资源）？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "5. 执行自动修复..."
    
    if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
        echo "删除 Longhorn Node 资源..."
        kubectl delete nodes.longhorn.io -n longhorn-system "$NODE_NAME" 2>/dev/null || true
        
        echo "等待 Node 资源重建..."
        sleep 10
        
        MAX_WAIT=300
        ELAPSED=0
        INTERVAL=5
        
        while [ $ELAPSED -lt $MAX_WAIT ]; do
            if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
                STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
                if [ "$STATUS" = "True" ]; then
                    echo "✓ Node 资源已重建并就绪"
                    break
                fi
            fi
            
            echo "  [$(date +%H:%M:%S)] 等待中..."
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
        done
        
        if [ $ELAPSED -ge $MAX_WAIT ]; then
            echo "⚠️  等待超时，请手动检查"
        fi
    else
        echo "Node 资源不存在，等待创建..."
    fi
    
    echo ""
    echo "重启 manager 以应用更改..."
    kubectl delete pod -n longhorn-system -l app=longhorn-manager
    sleep 10
fi

# 6. 验证修复
echo ""
echo "6. 验证修复..."
sleep 5

if [ -n "$MANAGER_POD" ]; then
    NEW_MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$NEW_MANAGER_POD" ]; then
        echo "检查新的 Manager 日志..."
        kubectl logs -n longhorn-system "$NEW_MANAGER_POD" --tail=50 2>&1 | grep -i "mismatching\|disk\|error" | tail -5 || echo "未发现磁盘错误"
    fi
fi

echo ""
echo "=== 完成 ==="
echo ""
echo "如果问题仍然存在:"
echo "  1. 检查节点上的磁盘路径: /var/lib/longhorn"
echo "  2. 通过 Longhorn UI 手动配置磁盘"
echo "  3. 或编辑 Node 资源手动配置"

