#!/bin/bash

# 详细诊断 Init Container 问题

echo "=== 详细诊断 Init Container 问题 ==="
echo ""

# 1. 获取 Pod 信息
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$DEPLOYER_POD" ]; then
    echo "❌ 未找到 driver-deployer Pod"
    exit 1
fi

echo "Pod: $DEPLOYER_POD"
echo ""

# 2. 查看 Pod 完整状态
echo "1. Pod 完整状态:"
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o yaml | grep -A 50 "status:" | head -60
echo ""

# 3. 查看 Init Container 状态详情
echo "2. Init Container 状态详情:"
INIT_STATE=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null)
echo "Init Container 状态: $INIT_STATE"
echo ""

# 检查是否有错误
INIT_TERMINATED=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0].lastState.terminated}' 2>/dev/null)
if [ -n "$INIT_TERMINATED" ] && [ "$INIT_TERMINATED" != "null" ]; then
    echo "⚠️  Init Container 曾经终止过"
    EXIT_CODE=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null)
    REASON=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
    echo "退出码: $EXIT_CODE"
    echo "原因: $REASON"
    echo ""
fi

# 4. 查看 Init Container 日志
echo "3. Init Container 日志（最后 50 行）:"
echo "---"
kubectl logs -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager --tail=50 2>&1
echo "---"
echo ""

# 5. 检查网络连接
echo "4. 检查网络连接:"
echo "测试 DNS 解析..."
if kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- nslookup longhorn-backend 2>/dev/null | grep -q "Address"; then
    echo "✓ DNS 解析正常"
else
    echo "⚠️  DNS 解析可能有问题"
    kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- nslookup longhorn-backend 2>&1 | head -10
fi
echo ""

echo "测试 Service 连接..."
if kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- sh -c "timeout 2 nc -zv longhorn-backend 9500 2>&1" 2>/dev/null | grep -q "succeeded\|open"; then
    echo "✓ 端口 9500 可访问"
else
    echo "⚠️  端口 9500 可能不可访问"
    kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- sh -c "timeout 2 nc -zv longhorn-backend 9500 2>&1" 2>&1 | head -5
fi
echo ""

# 6. 测试 API 访问
echo "5. 测试 API 访问:"
if kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- sh -c "command -v curl >/dev/null 2>&1" 2>/dev/null; then
    HTTP_CODE=$(kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- curl -m 3 -s -o /dev/null -w "%{http_code}" http://longhorn-backend:9500/v1 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ API 返回 200（正常）"
    else
        echo "⚠️  API 返回: $HTTP_CODE（期望 200）"
        echo "尝试获取详细响应:"
        kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- curl -m 3 -s http://longhorn-backend:9500/v1 2>&1 | head -10
    fi
else
    echo "ℹ️  Init Container 中没有 curl，无法直接测试"
    echo "检查 Init Container 中的工具:"
    kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- sh -c "ls -la /usr/bin/ | grep -E 'curl|wget|nc'" 2>&1 | head -10
fi
echo ""

# 7. 检查 manager 状态
echo "6. 检查 longhorn-manager 状态:"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    MANAGER_READY=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    echo "Manager Pod: $MANAGER_POD"
    echo "状态: $MANAGER_STATUS"
    echo "就绪: $MANAGER_READY"
    
    # 测试 manager 的 API
    if [ "$MANAGER_STATUS" = "Running" ] && [ "$MANAGER_READY" = "true" ]; then
        echo "测试 manager API:"
        HTTP_CODE=$(kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://localhost:9500/v1 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "✓ Manager API 正常（返回 200）"
        else
            echo "⚠️  Manager API 返回: $HTTP_CODE"
        fi
    fi
else
    echo "❌ 未找到 manager Pod"
fi
echo ""

# 8. 检查 Service 和 Endpoints
echo "7. 检查 Service 和 Endpoints:"
kubectl get svc,endpoints -n longhorn-system longhorn-backend
echo ""

# 9. 查看 Pod 事件
echo "8. Pod 事件:"
kubectl describe pod -n longhorn-system "$DEPLOYER_POD" | grep -A 30 "Events:" | head -35
echo ""

# 10. 检查 Init Container 镜像
echo "9. Init Container 配置:"
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.spec.initContainers[0]}' | python3 -m json.tool 2>/dev/null | head -20 || \
kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o yaml | grep -A 10 "initContainers:" | head -15
echo ""

# 11. 提供解决方案
echo "10. 可能的原因和解决方案:"
echo ""

# 检查是否是网络问题
if kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- nslookup longhorn-backend 2>/dev/null | grep -q "can't resolve\|NXDOMAIN"; then
    echo "❌ DNS 解析失败"
    echo "   解决: 检查 CoreDNS 和网络配置"
elif [ -n "$INIT_TERMINATED" ] && [ "$INIT_TERMINATED" != "null" ]; then
    echo "⚠️  Init Container 曾经崩溃"
    echo "   可能原因:"
    echo "   - 网络连接问题"
    echo "   - API 响应超时"
    echo "   - 容器资源不足"
    echo ""
    echo "   解决: 检查上述日志和网络连接"
else
    echo "可能原因:"
    echo "  1. API 响应慢或超时"
    echo "  2. 网络连接问题"
    echo "  3. Init Container 中的 curl 命令执行失败"
    echo ""
    echo "建议:"
    echo "  - 查看 Init Container 日志确认具体错误"
    echo "  - 检查 manager API 是否真的返回 200"
    echo "  - 检查网络连接"
fi

echo ""
echo "=== 完成 ==="

