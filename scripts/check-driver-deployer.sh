#!/bin/bash

# 检查 longhorn-driver-deployer 状态

echo "=== 检查 longhorn-driver-deployer ==="

# 1. 获取 Pod 名称
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$DEPLOYER_POD" ]; then
    echo "❌ 未找到 longhorn-driver-deployer Pod"
    exit 1
fi

echo "Pod: $DEPLOYER_POD"
echo ""

# 2. 检查 Pod 状态
echo "1. Pod 状态:"
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o wide
echo ""

# 3. 检查 Init Container 状态
echo "2. Init Container 状态:"
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[*].name}' 2>/dev/null
echo ""

# 4. 查看 Init Container 日志（关键）
echo "3. Init Container 日志 (wait-longhorn-manager):"
echo "---"
kubectl logs -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager --tail=50 2>&1
echo "---"
echo ""

# 5. 检查 longhorn-manager 状态
echo "4. longhorn-manager 状态:"
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null)
if [ -n "$MANAGER_PODS" ]; then
    echo "$MANAGER_PODS"
    echo ""
    
    READY_COUNT=$(echo "$MANAGER_PODS" | grep -c "Running" || echo "0")
    TOTAL_COUNT=$(echo "$MANAGER_PODS" | wc -l | tr -d ' ')
    
    if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
        echo "✓ longhorn-manager 已就绪 ($READY_COUNT/$TOTAL_COUNT)"
    else
        echo "⚠️  longhorn-manager 未完全就绪 ($READY_COUNT/$TOTAL_COUNT)"
        echo ""
        echo "检查 manager 日志:"
        MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$MANAGER_POD" ]; then
            echo "最近的日志:"
            kubectl logs -n longhorn-system "$MANAGER_POD" --tail=10 2>&1 | tail -5
        fi
    fi
else
    echo "❌ 未找到 longhorn-manager Pods"
fi
echo ""

# 6. 检查 Pod 事件
echo "5. Pod 事件:"
kubectl describe pod -n longhorn-system "$DEPLOYER_POD" | grep -A 20 "Events:" | head -25
echo ""

# 7. 提供解决方案
echo "6. 解决方案:"
MANAGER_READY=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$MANAGER_READY" -eq 0 ]; then
    echo "  ⚠️  longhorn-manager 未就绪"
    echo "  需要先修复 manager:"
    echo "    1. 确保所有节点已安装 open-iscsi"
    echo "    2. 重启 manager: kubectl delete pod -n longhorn-system -l app=longhorn-manager"
    echo "    3. 等待 manager 就绪后，driver-deployer 会自动继续"
else
    echo "  ✓ longhorn-manager 已就绪"
    echo "  driver-deployer 应该会自动继续"
    echo "  如果长时间卡住（>5分钟），可以重启:"
    echo "    kubectl delete pod -n longhorn-system $DEPLOYER_POD"
fi

echo ""
echo "=== 完成 ==="

