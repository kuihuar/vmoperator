#!/bin/bash

# 验证 Backend API 并修复 driver-deployer

set -e

echo "=== 验证并修复 driver-deployer ==="
echo ""

# 1. 检查 manager 状态
echo "1. 检查 longhorn-manager 状态..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$MANAGER_POD" ]; then
    echo "❌ 未找到 longhorn-manager Pod"
    exit 1
fi

MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
MANAGER_READY=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)

echo "Manager Pod: $MANAGER_POD"
echo "状态: $MANAGER_STATUS"
echo "就绪: $MANAGER_READY"
echo ""

if [ "$MANAGER_STATUS" != "Running" ] || [ "$MANAGER_READY" != "true" ]; then
    echo "❌ longhorn-manager 未就绪"
    exit 1
fi

# 2. 检查 Service Endpoints
echo "2. 检查 longhorn-backend Service Endpoints..."
ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
if [ -z "$ENDPOINTS" ]; then
    echo "❌ Service 没有 Endpoints"
    exit 1
fi

echo "✓ Service 有 Endpoints: $ENDPOINTS"
echo ""

# 3. 测试 API（从 manager Pod 内部）
echo "3. 测试 Backend API（从 manager Pod 内部）..."
HTTP_CODE=$(kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://localhost:9500/v1 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ API 返回 200（正常）"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "⚠️  无法测试 API（curl 可能不可用）"
else
    echo "⚠️  API 返回: $HTTP_CODE（期望 200）"
fi
echo ""

# 4. 测试从 Service 访问
echo "4. 测试从 Service 访问..."
# 尝试从另一个 Pod 访问（如果可能）
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    echo "从 driver-deployer Init Container 测试..."
    # 尝试在 Init Container 中测试（如果支持 curl）
    if kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- sh -c "command -v curl >/dev/null 2>&1" 2>/dev/null; then
        HTTP_CODE=$(kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://longhorn-backend:9500/v1 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "✓ 从 driver-deployer 可以访问 API（返回 200）"
            echo "   Init Container 应该会自动完成"
        else
            echo "⚠️  从 driver-deployer 访问返回: $HTTP_CODE"
        fi
    else
        echo "ℹ️  Init Container 中没有 curl，无法直接测试"
    fi
fi
echo ""

# 5. 检查 driver-deployer 状态
echo "5. 检查 driver-deployer 状态..."
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    DEPLOYER_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Driver Deployer Pod: $DEPLOYER_POD"
    echo "状态: $DEPLOYER_STATUS"
    
    if [ "$DEPLOYER_STATUS" = "Running" ]; then
        echo "✓ driver-deployer 已就绪"
    elif [ "$DEPLOYER_STATUS" = "PodInitializing" ]; then
        echo "⚠️  driver-deployer 仍在初始化中"
        echo ""
        echo "由于 manager 和 Service 都已就绪，建议重启 driver-deployer:"
        echo "  kubectl delete pod -n longhorn-system $DEPLOYER_POD"
    else
        echo "⚠️  driver-deployer 状态: $DEPLOYER_STATUS"
    fi
else
    echo "未找到 driver-deployer Pod"
fi
echo ""

# 6. 提供解决方案
echo "6. 解决方案:"
if [ "$MANAGER_STATUS" = "Running" ] && [ "$MANAGER_READY" = "true" ] && [ -n "$ENDPOINTS" ]; then
    echo "✓ 所有条件已满足："
    echo "  - longhorn-manager 已就绪"
    echo "  - longhorn-backend Service 有 Endpoints"
    echo ""
    echo "如果 driver-deployer 仍然卡住，重启它:"
    echo "  kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
    echo ""
    echo "重启后，Init Container 应该能够检测到 API 并完成。"
else
    echo "⚠️  某些条件未满足，请检查上述输出"
fi

echo ""
echo "=== 完成 ==="

