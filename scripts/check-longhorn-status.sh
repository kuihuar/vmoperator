#!/bin/bash

# 检查 Longhorn 完整状态

echo "=== 检查 Longhorn 状态 ==="

# 1. 检查所有 Pods
echo "1. Longhorn Pods 状态:"
kubectl get pods -n longhorn-system
echo ""

# 2. 检查 longhorn-manager
echo "2. longhorn-manager 状态:"
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_MANAGER=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$READY_MANAGER" -gt 0 ]; then
    echo "✓ longhorn-manager 运行正常 ($READY_MANAGER/$MANAGER_PODS)"
else
    echo "❌ longhorn-manager 未就绪 ($READY_MANAGER/$MANAGER_PODS)"
    echo ""
    echo "检查 longhorn-manager 日志:"
    MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$MANAGER_POD" ]; then
        echo "Pod: $MANAGER_POD"
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=20 2>&1 | tail -10
    fi
fi
echo ""

# 3. 检查 longhorn-driver-deployer
echo "3. longhorn-driver-deployer 状态:"
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    DEPLOYER_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Pod: $DEPLOYER_POD"
    echo "状态: $DEPLOYER_STATUS"
    
    if [ "$DEPLOYER_STATUS" = "Pending" ] || [ "$DEPLOYER_STATUS" = "PodInitializing" ]; then
        echo ""
        echo "Init Container 日志:"
        kubectl logs -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager --tail=20 2>&1 || echo "无法获取 Init Container 日志"
        
        echo ""
        echo "Pod 详情:"
        kubectl describe pod -n longhorn-system "$DEPLOYER_POD" | grep -A 15 "Events:" | head -20
    fi
else
    echo "未找到 longhorn-driver-deployer Pod"
fi
echo ""

# 4. 检查 iscsi 安装
echo "4. 检查节点 iscsi 安装状态:"
echo "（需要在节点上执行: iscsiadm --version）"
echo ""

# 5. 提供解决方案
echo "5. 解决方案:"
if [ "$READY_MANAGER" -eq 0 ]; then
    echo "  ⚠️  longhorn-manager 未就绪，需要先修复:"
    echo "     1. 确保所有节点已安装 open-iscsi"
    echo "     2. 重启 longhorn-manager:"
    echo "        kubectl delete pod -n longhorn-system -l app=longhorn-manager"
    echo "     3. 等待 manager 就绪后，driver-deployer 会自动继续"
else
    echo "  ✓ longhorn-manager 已就绪"
    echo "  ⚠️  driver-deployer 可能还在等待，稍等片刻或重启:"
    echo "     kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
fi
echo ""

echo "=== 完成 ==="

