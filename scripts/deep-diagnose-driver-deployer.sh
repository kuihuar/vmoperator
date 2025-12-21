#!/bin/bash

# 深度诊断 longhorn-driver-deployer Init:0/1 问题

set -e

POD_NAME="${1}"

echo "=== 深度诊断 longhorn-driver-deployer Init:0/1 问题 ==="
echo ""

# 1. 获取 Pod 名称
if [ -z "$POD_NAME" ]; then
    POD_NAME=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD_NAME" ]; then
        echo "❌ driver-deployer Pod 不存在"
        exit 1
    fi
fi

echo "Pod 名称: $POD_NAME"
echo ""

# 2. 检查 Pod 详细状态
echo "1. 检查 Pod 详细状态..."
kubectl get pod -n longhorn-system "$POD_NAME" -o yaml | grep -A 30 "status:" | head -40
echo ""

# 3. 检查 Init Container 详细信息
echo "2. 检查 Init Container 详细信息..."
INIT_CONTAINERS=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null)
if [ -z "$INIT_CONTAINERS" ]; then
    echo "❌ 未找到 Init Containers"
    exit 1
fi

echo "Init Containers: $INIT_CONTAINERS"
echo ""

for init in $INIT_CONTAINERS; do
    echo "--- Init Container: $init ---"
    
    # 检查状态
    INIT_STATUS=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath="{.status.initContainerStatuses[?(@.name=='$init')]}" 2>/dev/null)
    if [ -n "$INIT_STATUS" ]; then
        echo "状态:"
        echo "$INIT_STATUS" | python3 -m json.tool 2>/dev/null || echo "$INIT_STATUS"
    fi
    echo ""
    
    # 检查日志
    echo "日志（最后 50 行）:"
    kubectl logs -n longhorn-system "$POD_NAME" -c "$init" --tail=50 2>&1 | tail -50
    echo ""
    
    # 检查是否有错误
    echo "错误信息:"
    kubectl logs -n longhorn-system "$POD_NAME" -c "$init" 2>&1 | grep -iE "error|fail|timeout|refused|cannot|unable" | tail -10 || echo "  没有明显的错误"
    echo ""
done

# 4. 检查 longhorn-backend Service
echo "3. 检查 longhorn-backend Service..."
if kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    echo "✓ Service 存在"
    kubectl get svc -n longhorn-system longhorn-backend -o yaml | grep -E "name:|namespace:|clusterIP:|port:|targetPort:" | head -10
    echo ""
    
    SVC_IP=$(kubectl get svc -n longhorn-system longhorn-backend -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    SVC_PORT=$(kubectl get svc -n longhorn-system longhorn-backend -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    echo "Service IP: $SVC_IP"
    echo "Service Port: $SVC_PORT"
    echo "Service URL: http://longhorn-backend:${SVC_PORT}"
    echo ""
else
    echo "❌ Service 不存在（这是问题！）"
    echo ""
    echo "检查 Manager 是否运行:"
    kubectl get pods -n longhorn-system -l app=longhorn-manager
    exit 1
fi

# 5. 检查 Endpoints
echo "4. 检查 Endpoints..."
kubectl get endpoints -n longhorn-system longhorn-backend
echo ""

ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
if [ -z "$ENDPOINTS" ]; then
    echo "❌ 没有 Endpoints（这是问题！）"
    echo ""
    echo "检查 Manager Pods:"
    kubectl get pods -n longhorn-system -l app=longhorn-manager
    echo ""
    echo "Manager Pods 状态:"
    MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    for mgr in $MANAGER_PODS; do
        STATUS=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.phase}' 2>/dev/null)
        READY=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
        echo "  $mgr: $STATUS (Ready: $READY)"
    done
    echo ""
    echo "解决方案: 等待 Manager 就绪，或重启 Manager"
    echo "  kubectl delete pod -n longhorn-system -l app=longhorn-manager"
else
    echo "✓ 有 Endpoints: $ENDPOINTS"
    ENDPOINT_IP=$(echo $ENDPOINTS | awk '{print $1}')
    echo "第一个 Endpoint IP: $ENDPOINT_IP"
fi
echo ""

# 6. 从 Pod 内测试网络连接
echo "5. 从 driver-deployer Pod 内测试网络连接..."
FIRST_INIT=$(echo $INIT_CONTAINERS | awk '{print $1}')

if [ -n "$FIRST_INIT" ]; then
    echo "使用 Init Container: $FIRST_INIT"
    echo ""
    
    # 测试 DNS 解析
    echo "5.1 测试 DNS 解析..."
    kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- nslookup longhorn-backend 2>&1 | head -10 || \
    kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- getent hosts longhorn-backend 2>&1 || \
    echo "  DNS 解析失败"
    echo ""
    
    # 测试 Service 连接
    echo "5.2 测试 Service 连接..."
    kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- wget -qO- --timeout=5 "http://longhorn-backend:9500/v1" 2>&1 | head -10 || \
    kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- curl -s --max-time 5 "http://longhorn-backend:9500/v1" 2>&1 | head -10 || \
    echo "  HTTP 连接失败"
    echo ""
    
    # 测试直接 IP 连接
    if [ -n "$ENDPOINT_IP" ]; then
        echo "5.3 测试直接 IP 连接 ($ENDPOINT_IP:9500)..."
        kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- wget -qO- --timeout=5 "http://$ENDPOINT_IP:9500/v1" 2>&1 | head -10 || \
        kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- curl -s --max-time 5 "http://$ENDPOINT_IP:9500/v1" 2>&1 | head -10 || \
        echo "  直接 IP 连接也失败"
        echo ""
    fi
    
    # 检查 Pod 网络
    echo "5.4 检查 Pod 网络配置..."
    kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- ip addr show 2>&1 | grep -E "inet |^[0-9]+:" | head -10 || \
    echo "  无法查看网络配置"
    echo ""
    
    # 检查路由
    echo "5.5 检查路由..."
    kubectl exec -n longhorn-system "$POD_NAME" -c "$FIRST_INIT" -- ip route show 2>&1 | head -10 || \
    echo "  无法查看路由"
    echo ""
fi

# 7. 检查 Manager Pods
echo "6. 检查 Manager Pods..."
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_PODS" ]; then
    echo "Manager Pods:"
    for mgr in $MANAGER_PODS; do
        STATUS=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.phase}' 2>/dev/null)
        READY=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
        POD_IP=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.podIP}' 2>/dev/null)
        echo "  $mgr:"
        echo "    状态: $STATUS"
        echo "    就绪: $READY"
        echo "    IP: $POD_IP"
        
        # 检查是否监听 9500 端口
        if [ "$STATUS" = "Running" ]; then
            echo "    检查 9500 端口..."
            kubectl exec -n longhorn-system "$mgr" -- netstat -tlnp 2>/dev/null | grep 9500 || \
            kubectl exec -n longhorn-system "$mgr" -- ss -tlnp 2>/dev/null | grep 9500 || \
            echo "      无法检查（可能需要更多权限）"
        fi
        echo ""
    done
    
    # 检查 Manager 日志（最近错误）
    FIRST_MANAGER=$(echo $MANAGER_PODS | awk '{print $1}')
    echo "Manager 日志（最近 20 行，查找错误）:"
    kubectl logs -n longhorn-system "$FIRST_MANAGER" --tail=20 2>&1 | grep -iE "error|fail|listen|9500" | tail -10 || \
    echo "  没有明显的错误"
else
    echo "❌ 没有 Manager Pods"
fi
echo ""

# 8. 检查事件
echo "7. 检查相关事件..."
kubectl get events -n longhorn-system --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' | tail -15
echo ""

# 9. 检查网络策略
echo "8. 检查网络策略..."
NETWORK_POLICIES=$(kubectl get networkpolicies -n longhorn-system 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETWORK_POLICIES" -gt 1 ]; then
    echo "发现 $NETWORK_POLICIES 个网络策略:"
    kubectl get networkpolicies -n longhorn-system
    echo "⚠️  网络策略可能阻止连接"
else
    echo "✓ 没有网络策略限制"
fi
echo ""

# 10. 总结和建议
echo "=== 诊断总结 ==="
echo ""

PROBLEMS=0

# 检查关键问题
if [ -z "$ENDPOINTS" ]; then
    echo "❌ 问题 1: longhorn-backend 没有 Endpoints"
    echo "   原因: Manager Pod 未运行或未就绪"
    echo "   解决:"
    echo "     1. 检查 Manager: kubectl get pods -n longhorn-system -l app=longhorn-manager"
    echo "     2. 查看日志: kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo "     3. 如果 Manager 有问题，修复后重启:"
    echo "        kubectl delete pod -n longhorn-system -l app=longhorn-manager"
    PROBLEMS=$((PROBLEMS + 1))
fi

# 检查 Manager 状态
RUNNING_MANAGERS=0
for mgr in $MANAGER_PODS; do
    STATUS=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Running" ]; then
        RUNNING_MANAGERS=$((RUNNING_MANAGERS + 1))
    fi
done

if [ $RUNNING_MANAGERS -eq 0 ]; then
    echo "❌ 问题 2: 没有运行中的 Manager Pods"
    echo "   解决: 检查 Manager 日志并修复问题"
    PROBLEMS=$((PROBLEMS + 1))
fi

# 检查 Init Container 状态
INIT_READY=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath='{.status.initContainerStatuses[0].ready}' 2>/dev/null)
if [ "$INIT_READY" != "true" ]; then
    echo "❌ 问题 3: Init Container 未就绪"
    echo "   原因: 无法连接到 longhorn-backend API"
    if [ -n "$ENDPOINTS" ]; then
        echo "   可能原因:"
        echo "     - 网络连接问题"
        echo "     - DNS 解析问题"
        echo "     - 防火墙规则"
    fi
    PROBLEMS=$((PROBLEMS + 1))
fi

if [ $PROBLEMS -eq 0 ]; then
    echo "✓ 未发现明显问题"
    echo ""
    echo "如果 Init Container 仍然卡住，可能原因:"
    echo "  1. Manager API 需要更多时间初始化"
    echo "  2. 网络延迟"
    echo ""
    echo "建议:"
    echo "  1. 等待更长时间（10-15 分钟）"
    echo "  2. 重启 driver-deployer:"
    echo "     kubectl delete pod -n longhorn-system $POD_NAME"
else
    echo ""
    echo "发现 $PROBLEMS 个问题，请先解决这些问题"
fi

echo ""
echo "=== 完成 ==="
echo ""
echo "下一步操作:"
echo "  1. 如果 Manager 未运行，修复 Manager 问题"
echo "  2. 如果 Manager 运行但无 Endpoints，等待 Manager 完全就绪"
echo "  3. 如果一切正常但仍卡住，重启 driver-deployer:"
echo "     kubectl delete pod -n longhorn-system $POD_NAME"
echo ""

