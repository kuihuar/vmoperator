#!/bin/bash

# 检查 Longhorn Backend API 状态

echo "=== 检查 Longhorn Backend API ==="
echo ""

# 1. 解释等待逻辑
echo "1. Init Container 等待逻辑:"
echo "   Init Container 在等待: http://longhorn-backend:9500/v1"
echo "   它会每 2 秒检查一次，直到返回 HTTP 200 状态码"
echo "   这个 API 由 longhorn-manager 提供"
echo ""

# 2. 检查 longhorn-backend Service
echo "2. 检查 longhorn-backend Service:"
if kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    echo "✓ longhorn-backend Service 存在"
    kubectl get svc -n longhorn-system longhorn-backend
    echo ""
    
    # 检查 Service 的 Endpoints
    echo "   Endpoints:"
    kubectl get endpoints -n longhorn-system longhorn-backend
    echo ""
    
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -z "$ENDPOINTS" ]; then
        echo "   ❌ Service 没有 Endpoints（没有 Pod 在运行）"
        echo "   这意味着 longhorn-manager Pod 未就绪"
    else
        echo "   ✓ Service 有 Endpoints: $ENDPOINTS"
    fi
else
    echo "❌ longhorn-backend Service 不存在"
fi
echo ""

# 3. 检查 longhorn-manager Pods
echo "3. 检查 longhorn-manager Pods:"
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager 2>/dev/null)
if [ -n "$MANAGER_PODS" ]; then
    echo "$MANAGER_PODS"
    echo ""
    
    # 检查每个 Pod 的状态
    while IFS= read -r line; do
        if [[ $line == *"NAME"* ]]; then
            continue
        fi
        POD_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        READY=$(echo "$line" | awk '{print $2}')
        
        echo "   Pod: $POD_NAME"
        echo "   状态: $STATUS, 就绪: $READY"
        
        if [ "$STATUS" = "Running" ] && [[ "$READY" == "1/1" ]]; then
            echo "   ✓ 已就绪"
            
            # 尝试访问 API
            echo "   测试 API 访问:"
            if kubectl exec -n longhorn-system "$POD_NAME" -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://localhost:9500/v1 2>/dev/null | grep -q "200"; then
                echo "   ✓ API 可访问（返回 200）"
            else
                echo "   ⚠️  API 不可访问或未返回 200"
            fi
        elif [ "$STATUS" = "CrashLoopBackOff" ]; then
            echo "   ❌ 崩溃循环"
            echo "   查看日志:"
            kubectl logs -n longhorn-system "$POD_NAME" --tail=10 2>&1 | tail -5
        else
            echo "   ⚠️  未就绪"
        fi
        echo ""
    done <<< "$MANAGER_PODS"
else
    echo "❌ 未找到 longhorn-manager Pods"
fi

# 4. 检查网络连接
echo "4. 从 driver-deployer Pod 测试连接:"
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    echo "   Driver Deployer Pod: $DEPLOYER_POD"
    echo "   测试连接到 longhorn-backend:9500..."
    
    # 尝试在 Init Container 中测试（如果可能）
    if kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://longhorn-backend:9500/v1 2>/dev/null; then
        HTTP_CODE=$(kubectl exec -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager -- curl -m 2 -s -o /dev/null -w "%{http_code}" http://longhorn-backend:9500/v1 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "   ✓ 连接成功，返回 200"
        else
            echo "   ⚠️  连接成功，但返回: $HTTP_CODE"
        fi
    else
        echo "   ❌ 无法连接（可能 Init Container 不支持 curl，或服务未就绪）"
    fi
else
    echo "   未找到 driver-deployer Pod"
fi
echo ""

# 5. 提供解决方案
echo "5. 解决方案:"
MANAGER_READY=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running.*1/1" || echo "0")

if [ "$MANAGER_READY" -gt 0 ]; then
    echo "   ✓ longhorn-manager 已就绪"
    echo "   Backend API 应该可用"
    echo "   driver-deployer 应该会自动继续"
    echo "   如果长时间卡住（>5分钟），可以重启 driver-deployer:"
    echo "     kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
else
    echo "   ❌ longhorn-manager 未就绪"
    echo "   需要先修复 manager:"
    echo "     1. 检查 manager 日志: kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo "     2. 如果是 iscsi 问题，安装 open-iscsi"
    echo "     3. 重启 manager: kubectl delete pod -n longhorn-system -l app=longhorn-manager"
fi

echo ""
echo "=== 完成 ==="

