#!/bin/bash

# 检查 k3s 网络配置

echo "=== 检查 k3s 网络配置 ==="
echo ""

# 1. 检查 k3s 服务状态
echo "1. 检查 k3s 服务状态..."
if systemctl is-active --quiet k3s; then
    echo "✓ k3s 服务运行中"
    systemctl status k3s --no-pager | head -10
else
    echo "❌ k3s 服务未运行"
fi
echo ""

# 2. 检查 k3s 网络配置
echo "2. 检查 k3s 网络配置..."
if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    echo "k3s 配置文件存在"
    echo "API Server 地址:"
    grep -E "server:" /etc/rancher/k3s/k3s.yaml | head -1
else
    echo "⚠️  k3s 配置文件不存在"
fi
echo ""

# 3. 检查 CNI 配置
echo "3. 检查 CNI 配置..."
CNI_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if [ -d "$CNI_PATH" ]; then
    echo "CNI 配置路径: $CNI_PATH"
    echo "CNI 配置文件:"
    ls -la "$CNI_PATH" 2>/dev/null || echo "  路径不可访问（需要 root）"
    
    # 尝试读取 CNI 配置
    if sudo test -d "$CNI_PATH"; then
        echo ""
        echo "CNI 配置内容:"
        sudo ls -la "$CNI_PATH" | grep -E "\.(conf|conflist)$" | while read line; do
            FILE=$(echo "$line" | awk '{print $NF}')
            if [ -n "$FILE" ]; then
                echo "  文件: $FILE"
                sudo cat "$CNI_PATH/$FILE" 2>/dev/null | head -20 | sed 's/^/    /'
            fi
        done
    fi
else
    echo "⚠️  CNI 配置路径不存在: $CNI_PATH"
fi
echo ""

# 4. 检查 k3s 使用的 CNI
echo "4. 检查 k3s 使用的 CNI..."
# 检查 flannel
if kubectl get daemonset -n kube-system kube-flannel-ds 2>/dev/null | grep -q kube-flannel; then
    echo "✓ 使用 Flannel CNI"
    kubectl get pods -n kube-system | grep flannel | head -3
elif kubectl get daemonset -n kube-system calico-node 2>/dev/null | grep -q calico; then
    echo "✓ 使用 Calico CNI"
    kubectl get pods -n kube-system | grep calico | head -3
elif kubectl get daemonset -n kube-system cilium 2>/dev/null | grep -q cilium; then
    echo "✓ 使用 Cilium CNI"
    kubectl get pods -n kube-system | grep cilium | head -3
else
    echo "⚠️  未检测到标准 CNI，k3s 可能使用内置 CNI"
    echo "检查 k3s 内置网络组件:"
    kubectl get pods -n kube-system | grep -E "coredns|traefik|local-path" | head -5
fi
echo ""

# 5. 检查 Pod 网络
echo "5. 检查 Pod 网络..."
POD_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m 1 cluster-cidr | cut -d'"' -f4 || echo "未知")
SERVICE_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m 1 service-cluster-ip-range | cut -d'"' -f4 || echo "未知")
echo "Pod CIDR: $POD_CIDR"
echo "Service CIDR: $SERVICE_CIDR"
echo ""

# 6. 检查节点网络
echo "6. 检查节点网络..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NODE_NAME" ]; then
    echo "节点名称: $NODE_NAME"
    NODE_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    echo "节点 IP: $NODE_IP"
    
    # 检查节点上的网络接口
    echo "节点网络接口:"
    kubectl debug node/"$NODE_NAME" -it --image=busybox -- sh -c "ip addr show" 2>/dev/null | grep -E "^[0-9]+:|inet " | head -10 || \
    echo "  无法直接查看（需要节点访问权限）"
fi
echo ""

# 7. 检查 longhorn-backend Service
echo "7. 检查 longhorn-backend Service..."
if kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    echo "✓ longhorn-backend Service 存在"
    kubectl get svc -n longhorn-system longhorn-backend -o wide
    echo ""
    
    # 检查 Endpoints
    echo "Endpoints:"
    kubectl get endpoints -n longhorn-system longhorn-backend
    echo ""
    
    # 检查 Service IP
    SVC_IP=$(kubectl get svc -n longhorn-system longhorn-backend -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    SVC_PORT=$(kubectl get svc -n longhorn-system longhorn-backend -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    echo "Service IP: $SVC_IP"
    echo "Service Port: $SVC_PORT"
    echo ""
    
    # 尝试从 Pod 内访问
    echo "测试从 Pod 内访问 longhorn-backend..."
    TEST_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$TEST_POD" ]; then
        echo "使用 Manager Pod 测试: $TEST_POD"
        kubectl exec -n longhorn-system "$TEST_POD" -- wget -qO- --timeout=5 "http://longhorn-backend:9500/v1" 2>&1 | head -5 || \
        kubectl exec -n longhorn-system "$TEST_POD" -- curl -s --max-time 5 "http://longhorn-backend:9500/v1" 2>&1 | head -5 || \
        echo "  无法访问（可能需要更多时间）"
    else
        echo "  没有可用的 Manager Pod 进行测试"
    fi
else
    echo "❌ longhorn-backend Service 不存在"
fi
echo ""

# 8. 检查 driver-deployer 网络问题
echo "8. 检查 driver-deployer 网络问题..."
DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DRIVER_DEPLOYER" ]; then
    echo "Driver Deployer Pod: $DRIVER_DEPLOYER"
    STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "状态: $STATUS"
    echo ""
    
    # 检查 Init Container 日志
    echo "Init Container 日志:"
    kubectl logs -n longhorn-system "$DRIVER_DEPLOYER" -c wait-for-backend --tail=20 2>&1 | tail -10 || \
    kubectl logs -n longhorn-system "$DRIVER_DEPLOYER" --all-containers=true --tail=20 2>&1 | tail -10
    echo ""
    
    # 检查 Pod 网络
    echo "Pod IP:"
    POD_IP=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.podIP}' 2>/dev/null)
    echo "  $POD_IP"
    echo ""
    
    # 尝试从 Pod 内访问
    echo "从 Pod 内测试网络连接:"
    kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c wait-for-backend -- wget -qO- --timeout=5 "http://longhorn-backend:9500/v1" 2>&1 | head -5 || \
    kubectl exec -n longhorn-system "$DRIVER_DEPLOYER" -c wait-for-backend -- curl -s --max-time 5 "http://longhorn-backend:9500/v1" 2>&1 | head -5 || \
    echo "  无法访问（可能是网络问题）"
else
    echo "⚠️  driver-deployer Pod 不存在"
fi
echo ""

# 9. 检查 DNS
echo "9. 检查 DNS 解析..."
TEST_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$TEST_POD" ]; then
    echo "测试 DNS 解析 longhorn-backend..."
    kubectl exec -n longhorn-system "$TEST_POD" -- nslookup longhorn-backend 2>&1 | head -10 || \
    kubectl exec -n longhorn-system "$TEST_POD" -- getent hosts longhorn-backend 2>&1 || \
    echo "  DNS 解析可能有问题"
else
    echo "  没有可用的 Pod 进行 DNS 测试"
fi
echo ""

# 10. 检查网络策略
echo "10. 检查网络策略..."
NETWORK_POLICIES=$(kubectl get networkpolicies -n longhorn-system 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETWORK_POLICIES" -gt 1 ]; then
    echo "发现 $NETWORK_POLICIES 个网络策略:"
    kubectl get networkpolicies -n longhorn-system
else
    echo "✓ 没有网络策略限制"
fi
echo ""

# 11. 总结
echo "=== 网络诊断总结 ==="
echo ""

# 检查关键问题
ISSUES=0

# 检查 CNI
if ! kubectl get pods -n kube-system | grep -qE "flannel|calico|cilium"; then
    echo "ℹ️  k3s 使用内置 CNI（这是正常的）"
fi

# 检查 longhorn-backend
if ! kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    echo "❌ longhorn-backend Service 不存在（这是问题！）"
    ISSUES=$((ISSUES + 1))
fi

# 检查 Endpoints
ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
if [ -z "$ENDPOINTS" ]; then
    echo "❌ longhorn-backend 没有 Endpoints（Manager 可能未运行）"
    ISSUES=$((ISSUES + 1))
fi

# 检查 driver-deployer
if [ -n "$DRIVER_DEPLOYER" ]; then
    STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Init:0/1" ] || [ "$STATUS" = "Init:CrashLoopBackOff" ]; then
        echo "❌ driver-deployer 卡在 Init 状态"
        echo "   可能原因:"
        echo "     1. longhorn-backend API 不可访问"
        echo "     2. 网络连接问题"
        echo "     3. DNS 解析问题"
        ISSUES=$((ISSUES + 1))
    fi
fi

if [ $ISSUES -eq 0 ]; then
    echo "✓ 未发现明显的网络问题"
else
    echo ""
    echo "发现 $ISSUES 个问题，建议:"
    echo "  1. 检查 longhorn-manager 是否运行"
    echo "  2. 检查 longhorn-backend Service 和 Endpoints"
    echo "  3. 检查 Pod 网络连接"
    echo "  4. 查看 driver-deployer 日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true"
fi

echo ""
echo "=== 完成 ==="

