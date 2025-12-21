#!/bin/bash

# 诊断 driver-deployer 网络问题

echo "=== 诊断 driver-deployer 网络问题 ==="
echo ""

# 1. 检查 driver-deployer 状态
echo "1. 检查 driver-deployer 状态..."
DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$DRIVER_DEPLOYER" ]; then
    echo "❌ driver-deployer Pod 不存在"
    exit 1
fi

STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.phase}' 2>/dev/null)
echo "Pod: $DRIVER_DEPLOYER"
echo "状态: $STATUS"
echo ""

# 2. 检查 Init Container
echo "2. 检查 Init Container..."
INIT_CONTAINER=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null)
if [ -n "$INIT_CONTAINER" ]; then
    echo "Init Container: $INIT_CONTAINER"
    INIT_STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.initContainerStatuses[0].ready}' 2>/dev/null)
    INIT_STATE=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null)
    echo "状态: Ready=$INIT_STATUS, State=$INIT_STATE"
    echo ""
    
    echo "Init Container 日志:"
    kubectl logs -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" --tail=30 2>&1
else
    echo "⚠️  未找到 Init Container"
fi
echo ""

# 3. 检查 longhorn-backend Service
echo "3. 检查 longhorn-backend Service..."
if kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    echo "✓ Service 存在"
    kubectl get svc -n longhorn-system longhorn-backend -o yaml | grep -E "name:|namespace:|clusterIP:|port:" | head -10
    echo ""
    
    # 检查 Endpoints
    echo "Endpoints:"
    kubectl get endpoints -n longhorn-system longhorn-backend
    echo ""
    
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [ -z "$ENDPOINTS" ]; then
        echo "❌ 没有 Endpoints（Manager Pod 可能未运行或未就绪）"
        echo ""
        echo "检查 Manager Pods:"
        kubectl get pods -n longhorn-system -l app=longhorn-manager
    else
        echo "✓ 有 Endpoints: $ENDPOINTS"
    fi
else
    echo "❌ Service 不存在"
fi
echo ""

# 4. 检查 Manager Pods
echo "4. 检查 Manager Pods..."
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_PODS" ]; then
    echo "Manager Pods:"
    for pod in $MANAGER_PODS; do
        POD_STATUS=$(kubectl get pod -n longhorn-system "$pod" -o jsonpath='{.status.phase}' 2>/dev/null)
        POD_IP=$(kubectl get pod -n longhorn-system "$pod" -o jsonpath='{.status.podIP}' 2>/dev/null)
        echo "  $pod: $POD_STATUS (IP: $POD_IP)"
    done
    echo ""
    
    # 检查 Manager 是否监听 9500 端口
    FIRST_MANAGER=$(echo $MANAGER_PODS | awk '{print $1}')
    echo "检查 Manager 是否监听 9500 端口 ($FIRST_MANAGER)..."
    kubectl exec -n longhorn-system "$FIRST_MANAGER" -- netstat -tlnp 2>/dev/null | grep 9500 || \
    kubectl exec -n longhorn-system "$FIRST_MANAGER" -- ss -tlnp 2>/dev/null | grep 9500 || \
    echo "  无法检查（可能需要更多权限）"
else
    echo "❌ 没有 Manager Pods"
fi
echo ""

# 5. 测试网络连接
echo "5. 测试网络连接..."
if [ -n "$DRIVER_DEPLOYER" ]; then
    echo "从 driver-deployer Pod 测试连接..."
    
    # 测试 DNS 解析
    echo "测试 DNS 解析..."
    kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" -- nslookup longhorn-backend 2>&1 | head -10 || \
    kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" -- getent hosts longhorn-backend 2>&1 || \
    echo "  DNS 解析失败"
    echo ""
    
    # 测试 HTTP 连接
    echo "测试 HTTP 连接..."
    kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" -- wget -qO- --timeout=5 "http://longhorn-backend:9500/v1" 2>&1 | head -5 || \
    kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" -- curl -s --max-time 5 "http://longhorn-backend:9500/v1" 2>&1 | head -5 || \
    echo "  HTTP 连接失败"
    echo ""
    
    # 测试直接 IP 连接
    if [ -n "$ENDPOINTS" ]; then
        ENDPOINT_IP=$(echo $ENDPOINTS | awk '{print $1}')
        echo "测试直接 IP 连接 ($ENDPOINT_IP:9500)..."
        kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" -- wget -qO- --timeout=5 "http://$ENDPOINT_IP:9500/v1" 2>&1 | head -5 || \
        kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c "$INIT_CONTAINER" -- curl -s --max-time 5 "http://$ENDPOINT_IP:9500/v1" 2>&1 | head -5 || \
        echo "  直接 IP 连接也失败"
    fi
fi
echo ""

# 6. 检查 k3s 网络配置
echo "6. 检查 k3s 网络配置..."
CNI_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if sudo test -d "$CNI_PATH"; then
    echo "CNI 配置路径: $CNI_PATH"
    echo "CNI 配置文件:"
    sudo ls -la "$CNI_PATH" 2>/dev/null | grep -E "\.(conf|conflist)$" | head -5
else
    echo "⚠️  CNI 配置路径不存在或不可访问"
fi
echo ""

# 7. 检查 Pod 网络
echo "7. 检查 Pod 网络..."
POD_IP=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.podIP}' 2>/dev/null)
echo "Driver Deployer Pod IP: $POD_IP"

if [ -n "$ENDPOINTS" ]; then
    ENDPOINT_IP=$(echo $ENDPOINTS | awk '{print $1}')
    echo "Manager Pod IP: $ENDPOINT_IP"
    
    # 检查是否在同一网络
    POD_NETWORK=$(echo "$POD_IP" | cut -d'.' -f1-3)
    ENDPOINT_NETWORK=$(echo "$ENDPOINT_IP" | cut -d'.' -f1-3)
    if [ "$POD_NETWORK" = "$ENDPOINT_NETWORK" ]; then
        echo "✓ Pods 在同一网络段"
    else
        echo "⚠️  Pods 不在同一网络段（可能正常，取决于 CNI 配置）"
    fi
fi
echo ""

# 8. 总结和建议
echo "=== 诊断总结 ==="
echo ""

if [ -z "$ENDPOINTS" ]; then
    echo "❌ 问题: longhorn-backend 没有 Endpoints"
    echo ""
    echo "解决方案:"
    echo "  1. 检查 longhorn-manager Pods 是否运行:"
    echo "     kubectl get pods -n longhorn-system -l app=longhorn-manager"
    echo ""
    echo "  2. 如果 Manager 未运行，检查日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo ""
    echo "  3. 等待 Manager 就绪后，Endpoints 会自动创建"
elif [ "$STATUS" = "Init:0/1" ] || [ "$STATUS" = "Init:CrashLoopBackOff" ]; then
    echo "❌ 问题: driver-deployer 卡在 Init 状态"
    echo ""
    echo "可能原因:"
    echo "  1. longhorn-backend API 不可访问（网络问题）"
    echo "  2. DNS 解析失败"
    echo "  3. 防火墙或网络策略阻止连接"
    echo ""
    echo "解决方案:"
    echo "  1. 等待 Manager 完全就绪（可能需要几分钟）"
    echo "  2. 重启 driver-deployer:"
    echo "     kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
    echo ""
    echo "  3. 如果问题持续，检查网络连接:"
    echo "     ./scripts/check-k3s-network.sh"
else
    echo "✓ driver-deployer 状态正常"
fi

echo ""
echo "=== 完成 ==="

