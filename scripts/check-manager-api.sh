#!/bin/bash

# 检查 longhorn-manager API 服务

echo "=== 检查 longhorn-manager API 服务 ==="
echo ""

# 1. 检查 manager Pod
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$MANAGER_POD" ]; then
    echo "❌ 未找到 longhorn-manager Pod"
    exit 1
fi

echo "Manager Pod: $MANAGER_POD"
echo ""

# 2. 检查 manager 日志
echo "1. 检查 manager 日志（查找 API 相关）:"
kubectl logs -n longhorn-system "$MANAGER_POD" --tail=100 2>&1 | grep -i -E "api|server|listen|9500|error|fatal" | tail -20
echo ""

# 3. 检查 manager 是否监听 9500 端口
echo "2. 检查 manager 是否监听 9500 端口:"
if kubectl exec -n longhorn-system "$MANAGER_POD" -- netstat -tlnp 2>/dev/null | grep -q "9500"; then
    echo "✓ Manager 正在监听 9500 端口"
    kubectl exec -n longhorn-system "$MANAGER_POD" -- netstat -tlnp 2>/dev/null | grep "9500"
else
    echo "❌ Manager 未监听 9500 端口"
    echo "检查所有监听端口:"
    kubectl exec -n longhorn-system "$MANAGER_POD" -- netstat -tlnp 2>/dev/null | head -10 || echo "无法检查端口"
fi
echo ""

# 4. 检查进程
echo "3. 检查 manager 进程:"
kubectl exec -n longhorn-system "$MANAGER_POD" -- ps aux 2>/dev/null | grep -E "longhorn|manager" | head -10 || echo "无法检查进程"
echo ""

# 5. 尝试从 manager Pod 内部访问 API
echo "4. 从 manager Pod 内部测试 API:"
echo "测试 localhost:9500/v1..."
HTTP_CODE=$(kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -m 3 -s -o /dev/null -w "%{http_code}" http://localhost:9500/v1 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ API 返回 200（正常）"
elif echo "$HTTP_CODE" | grep -q "000"; then
    echo "❌ API 无法访问（curl 失败）"
    echo "详细错误:"
    kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -v http://localhost:9500/v1 2>&1 | head -20
else
    echo "⚠️  API 返回: $HTTP_CODE"
    echo "详细响应:"
    kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -s http://localhost:9500/v1 2>&1 | head -10
fi
echo ""

# 6. 检查 manager 容器状态
echo "5. Manager 容器状态:"
kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.containerStatuses[0]}' | python3 -m json.tool 2>/dev/null | head -20 || \
kubectl describe pod -n longhorn-system "$MANAGER_POD" | grep -A 10 "Containers:" | head -15
echo ""

# 7. 检查 manager 的 readiness probe
echo "6. 检查 readiness probe:"
READY_CONDITION=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")]}' 2>/dev/null)
echo "$READY_CONDITION" | python3 -m json.tool 2>/dev/null || echo "$READY_CONDITION"
echo ""

# 8. 检查 manager 的完整日志
echo "7. Manager 完整日志（最后 50 行）:"
kubectl logs -n longhorn-system "$MANAGER_POD" --tail=50 2>&1 | tail -30
echo ""

# 9. 提供解决方案
echo "8. 可能的原因和解决方案:"
echo ""
echo "如果 manager 未监听 9500 端口:"
echo "  1. Manager 可能还在启动中"
echo "  2. Manager 可能遇到错误"
echo "  3. 检查 manager 日志中的错误信息"
echo ""
echo "如果 manager 监听端口但 API 不可访问:"
echo "  1. 可能是网络问题"
echo "  2. 可能是 API 服务未正常启动"
echo "  3. 检查 manager 配置"
echo ""
echo "建议:"
echo "  1. 查看 manager 完整日志: kubectl logs -n longhorn-system $MANAGER_POD"
echo "  2. 检查 manager 配置: kubectl get configmap -n longhorn-system"
echo "  3. 如果问题持续，考虑重启 manager: kubectl delete pod -n longhorn-system $MANAGER_POD"

echo ""
echo "=== 完成 ==="

