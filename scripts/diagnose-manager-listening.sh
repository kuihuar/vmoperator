#!/bin/bash

# 诊断 Manager 监听问题

echo "=== 诊断 Manager 监听问题 ==="
echo ""

# 1. 检查 Manager 日志中的监听地址
echo "1. 检查 Manager 监听地址..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    echo "Manager Pod: $MANAGER_POD"
    echo ""
    echo "从日志中查找监听地址:"
    kubectl logs -n longhorn-system "$MANAGER_POD" --tail=100 2>&1 | grep -i "listening\|listen" | tail -5
    echo ""
    
    # 获取 Pod IP
    POD_IP=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.podIP}' 2>/dev/null)
    echo "Pod IP: $POD_IP"
    echo ""
fi

# 2. 检查 Manager 监听的端口
echo "2. 检查 Manager 监听的端口..."
if [ -n "$MANAGER_POD" ]; then
    echo "检查所有监听端口:"
    kubectl exec -n longhorn-system "$MANAGER_POD" -- netstat -tlnp 2>/dev/null | grep -E "LISTEN|Proto" || \
    kubectl exec -n longhorn-system "$MANAGER_POD" -- ss -tlnp 2>/dev/null | grep -E "LISTEN|State" || \
    echo "无法检查端口（netstat/ss 不可用）"
    echo ""
    
    # 尝试从 Pod IP 访问
    if [ -n "$POD_IP" ]; then
        echo "测试从 Pod IP 访问:"
        HTTP_CODE=$(kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://$POD_IP:9500/v1 2>&1 || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "✓ 从 Pod IP ($POD_IP:9500) 可以访问（返回 200）"
        else
            echo "⚠️  从 Pod IP 访问返回: $HTTP_CODE"
        fi
    fi
    echo ""
fi

# 3. 检查 Service 和 Endpoints
echo "3. 检查 Service 和 Endpoints..."
kubectl get svc,endpoints -n longhorn-system longhorn-backend
echo ""

ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
if [ -n "$ENDPOINTS" ]; then
    echo "Endpoints IP: $ENDPOINTS"
    if [ "$ENDPOINTS" = "$POD_IP" ]; then
        echo "✓ Endpoints 指向正确的 Pod IP"
    else
        echo "⚠️  Endpoints IP 与 Pod IP 不匹配"
    fi
fi
echo ""

# 4. 测试从 Service 访问
echo "4. 测试从 Service 访问..."
if [ -n "$MANAGER_POD" ]; then
    echo "从 manager Pod 内部测试 Service:"
    HTTP_CODE=$(kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://longhorn-backend:9500/v1 2>&1 || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ 从 Service (longhorn-backend:9500) 可以访问（返回 200）"
    else
        echo "⚠️  从 Service 访问返回: $HTTP_CODE"
        echo "详细错误:"
        kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -v http://longhorn-backend:9500/v1 2>&1 | head -15
    fi
fi
echo ""

# 5. 检查网络策略
echo "5. 检查网络策略..."
NETWORK_POLICIES=$(kubectl get networkpolicies -n longhorn-system 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETWORK_POLICIES" -gt 1 ]; then
    echo "发现网络策略，可能影响连接:"
    kubectl get networkpolicies -n longhorn-system
else
    echo "未发现网络策略"
fi
echo ""

# 6. 检查 k3s CNI
echo "6. 检查 k3s CNI 配置..."
if [ -d "/var/lib/rancher/k3s/agent/etc/cni/net.d" ]; then
    echo "CNI 配置目录存在"
    ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/ 2>/dev/null | head -5 || echo "无法访问（需要 root 权限）"
else
    echo "CNI 配置目录不存在或无法访问"
fi
echo ""

# 7. 分析问题
echo "7. 问题分析:"
echo ""
if kubectl logs -n longhorn-system "$MANAGER_POD" --tail=100 2>&1 | grep -q "Listening on.*9500"; then
    LISTEN_ADDR=$(kubectl logs -n longhorn-system "$MANAGER_POD" --tail=100 2>&1 | grep "Listening on.*9500" | tail -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:9500" || echo "")
    if [ -n "$LISTEN_ADDR" ]; then
        echo "Manager 正在监听: $LISTEN_ADDR"
        if echo "$LISTEN_ADDR" | grep -q "^10\."; then
            echo "✓ 监听 Pod IP（正常）"
            echo ""
            echo "问题可能是:"
            echo "  1. Service 到 Pod 的网络连接问题"
            echo "  2. k3s CNI 配置问题"
            echo "  3. Manager 需要监听 0.0.0.0:9500 而不是 Pod IP"
        fi
    fi
fi
echo ""

# 8. 提供解决方案
echo "8. 解决方案:"
echo ""
echo "选项 1: 检查 Service 连接（推荐）"
echo "  - Manager 已启动并监听"
echo "  - 检查 Service 到 Pod 的网络连接"
echo "  - 可能是 k3s CNI 的临时问题"
echo ""
echo "选项 2: 重启相关组件"
echo "  kubectl delete pod -n longhorn-system -l app=longhorn-manager"
echo "  kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
echo ""
echo "选项 3: 如果 StorageClass 已存在，忽略 driver-deployer"
echo "  - StorageClass 已创建，可以正常使用"
echo "  - driver-deployer 是可选组件"

echo ""
echo "=== 完成 ==="

