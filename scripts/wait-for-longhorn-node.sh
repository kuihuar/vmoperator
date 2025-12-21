#!/bin/bash

# 等待 Longhorn Node 资源创建

set -e

NODE_NAME="${1:-host1}"
MAX_WAIT="${2:-300}"  # 默认等待 5 分钟

echo "=== 等待 Longhorn Node 资源创建 ==="
echo "节点名称: $NODE_NAME"
echo "最大等待时间: ${MAX_WAIT} 秒"
echo ""

# 1. 检查 longhorn-manager 是否运行
echo "1. 检查 longhorn-manager..."
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -z "$MANAGER_PODS" ]; then
    echo "❌ longhorn-manager Pods 不存在"
    echo "请先确保 Longhorn 已安装并且 Manager 正在运行"
    exit 1
fi

RUNNING_MANAGERS=0
for pod in $MANAGER_PODS; do
    STATUS=$(kubectl get pod -n longhorn-system "$pod" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Running" ]; then
        RUNNING_MANAGERS=$((RUNNING_MANAGERS + 1))
    fi
done

if [ $RUNNING_MANAGERS -eq 0 ]; then
    echo "❌ 没有运行中的 longhorn-manager Pods"
    echo "检查 Manager 状态:"
    kubectl get pods -n longhorn-system -l app=longhorn-manager
    exit 1
fi

echo "✓ 发现 $RUNNING_MANAGERS 个运行中的 Manager Pods"
echo ""

# 2. 检查 Manager 日志（查看是否有错误）
echo "2. 检查 Manager 日志（最近 10 行）..."
FIRST_MANAGER=$(echo $MANAGER_PODS | awk '{print $1}')
kubectl logs -n longhorn-system "$FIRST_MANAGER" --tail=10 2>&1 | tail -10
echo ""

# 3. 等待 Node 资源创建
echo "3. 等待 Longhorn Node 资源创建..."
echo "（这可能需要几分钟，Manager 需要发现节点）"
echo ""

ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
        echo "✓ Longhorn Node 资源已创建！"
        echo ""
        
        # 显示 Node 资源信息
        echo "Node 资源信息:"
        kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -E "name:|namespace:|creationTimestamp:" | head -5
        echo ""
        
        # 检查 Node 状态
        NODE_READY=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$NODE_READY" = "True" ]; then
            echo "✓ Node 状态: Ready"
        else
            echo "⚠️  Node 状态: 未就绪"
        fi
        
        exit 0
    fi
    
    # 显示进度
    REMAINING=$((MAX_WAIT - ELAPSED))
    echo "  [$(date +%H:%M:%S)] 等待中... (剩余 ${REMAINING} 秒)"
    
    # 每 30 秒检查一次 Manager 状态
    if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        MANAGER_STATUS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        echo "    Manager 状态: $MANAGER_STATUS"
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

# 超时
echo ""
echo "❌ 等待超时，Longhorn Node 资源仍未创建"
echo ""

# 诊断
echo "诊断信息:"
echo ""

# 检查 Manager 状态
echo "1. Manager Pods 状态:"
kubectl get pods -n longhorn-system -l app=longhorn-manager
echo ""

# 检查 Manager 日志（错误）
echo "2. Manager 日志（最近 20 行，查找错误）:"
kubectl logs -n longhorn-system "$FIRST_MANAGER" --tail=20 2>&1 | grep -iE "error|fail|warn" | head -10 || echo "  没有明显的错误"
echo ""

# 检查 Kubernetes 节点
echo "3. Kubernetes 节点状态:"
kubectl get node "$NODE_NAME" -o wide
echo ""

# 检查节点标签
echo "4. 节点标签:"
kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels}' | python3 -m json.tool 2>/dev/null || \
kubectl get node "$NODE_NAME" --show-labels | grep -E "kubernetes.io|node-role"
echo ""

# 建议
echo "可能的原因和解决方案:"
echo ""
echo "1. Manager 需要更多时间发现节点"
echo "   解决: 再等待几分钟，或重启 Manager:"
echo "     kubectl delete pod -n longhorn-system -l app=longhorn-manager"
echo ""
echo "2. Manager 无法访问节点信息"
echo "   解决: 检查 Manager 的 RBAC 权限"
echo ""
echo "3. 节点名称不匹配"
echo "   解决: 检查实际的节点名称:"
echo "     kubectl get nodes"
echo "     然后使用正确的节点名称"
echo ""
echo "4. Longhorn 版本问题"
echo "   解决: 尝试使用最新版本重新安装:"
echo "     ./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn"
echo ""

exit 1

