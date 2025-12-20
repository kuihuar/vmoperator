#!/bin/bash

# 查看 longhorn-driver-deployer 的详细日志

echo "=== 查看 longhorn-driver-deployer 日志 ==="

# 1. 获取 Pod 名称
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$DEPLOYER_POD" ]; then
    echo "❌ 未找到 longhorn-driver-deployer Pod"
    exit 1
fi

echo "Pod: $DEPLOYER_POD"
echo ""

# 2. 查看 Init Container 日志（关键）
echo "1. Init Container 日志 (wait-longhorn-manager):"
echo "---"
kubectl logs -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager --tail=100 2>&1
echo "---"
echo ""

# 3. 查看 Pod 详情
echo "2. Pod 详情:"
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o yaml | grep -A 30 "status:" | head -40
echo ""

# 4. 查看 Pod 事件
echo "3. Pod 事件:"
kubectl describe pod -n longhorn-system "$DEPLOYER_POD" | grep -A 30 "Events:"
echo ""

# 5. 查看 Init Container 状态
echo "4. Init Container 状态:"
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[*]}' | jq '.' 2>/dev/null || \
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0]}' | python3 -m json.tool 2>/dev/null || \
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0].state}'
echo ""

# 6. 检查 longhorn-manager 状态
echo "5. longhorn-manager 状态:"
kubectl get pods -n longhorn-system -l app=longhorn-manager
echo ""

MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Manager Pod: $MANAGER_POD"
    echo "状态: $MANAGER_STATUS"
    
    if [ "$MANAGER_STATUS" != "Running" ]; then
        echo ""
        echo "Manager 未就绪，查看日志:"
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=30 2>&1 | tail -15
    fi
fi

echo ""
echo "=== 完成 ==="
echo ""
echo "关键信息:"
echo "  - Init Container 日志: kubectl logs -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager"
echo "  - Pod 详情: kubectl describe pod -n longhorn-system $DEPLOYER_POD"
echo "  - Pod 事件: kubectl get events -n longhorn-system --field-selector involvedObject.name=$DEPLOYER_POD"

