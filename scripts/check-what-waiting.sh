#!/bin/bash

# 检查 Init Container 在等待什么

echo "=== 检查 Init Container 在等待什么 ==="
echo ""

# 1. Init Container 的作用
echo "1. Init Container 'wait-longhorn-manager' 的作用:"
echo "   它在等待 longhorn-manager Pod 就绪（Running 状态）"
echo "   这是正常行为，但需要确保 manager 能够正常启动"
echo ""

# 2. 检查 longhorn-manager 状态
echo "2. 检查 longhorn-manager 状态:"
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager 2>/dev/null)

if [ -z "$MANAGER_PODS" ]; then
    echo "❌ 未找到 longhorn-manager Pods"
    echo "   这可能是问题所在！"
else
    echo "$MANAGER_PODS"
    echo ""
    
    # 检查每个 manager Pod 的状态
    while IFS= read -r line; do
        if [[ $line == *"NAME"* ]]; then
            continue
        fi
        POD_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        READY=$(echo "$line" | awk '{print $2}')
        
        echo "   Pod: $POD_NAME"
        echo "   状态: $STATUS"
        echo "   就绪: $READY"
        
        if [ "$STATUS" = "Running" ] && [[ "$READY" == "1/1" ]]; then
            echo "   ✓ 已就绪"
        elif [ "$STATUS" = "CrashLoopBackOff" ]; then
            echo "   ❌ 崩溃循环，需要修复"
            echo "   查看日志:"
            kubectl logs -n longhorn-system "$POD_NAME" --tail=10 2>&1 | tail -5
        elif [ "$STATUS" = "Pending" ]; then
            echo "   ⚠️  等待调度"
        elif [ "$STATUS" = "ContainerCreating" ]; then
            echo "   ⚠️  容器创建中"
        else
            echo "   ⚠️  状态异常: $STATUS"
        fi
        echo ""
    done <<< "$MANAGER_PODS"
fi

# 3. 检查 manager 的健康检查
echo "3. 检查 longhorn-manager 健康检查:"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    echo "   Manager Pod: $MANAGER_POD"
    
    # 检查 readiness probe
    READY_CONDITION=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    echo "   Ready 条件: $READY_CONDITION"
    
    # 检查容器状态
    CONTAINER_READY=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    echo "   容器就绪: $CONTAINER_READY"
    
    # 检查容器重启次数
    RESTARTS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    if [ -n "$RESTARTS" ] && [ "$RESTARTS" -gt 0 ]; then
        echo "   重启次数: $RESTARTS"
    fi
fi
echo ""

# 4. 检查 Init Container 的等待逻辑
echo "4. Init Container 等待逻辑:"
echo "   Init Container 'wait-longhorn-manager' 会:"
echo "   1. 检查 longhorn-manager Service 是否存在"
echo "   2. 检查 longhorn-manager Pod 是否 Running"
echo "   3. 检查 Pod 的 Ready 条件是否为 True"
echo "   4. 如果都满足，Init Container 完成，主容器启动"
echo ""

# 5. 提供解决方案
echo "5. 解决方案:"
MANAGER_STATUS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
MANAGER_READY=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

if [ "$MANAGER_STATUS" = "Running" ] && [ "$MANAGER_READY" = "true" ]; then
    echo "   ✓ longhorn-manager 已就绪"
    echo "   driver-deployer 应该会自动继续"
    echo "   如果长时间卡住（>5分钟），可以重启 driver-deployer:"
    echo "     kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
elif [ "$MANAGER_STATUS" = "CrashLoopBackOff" ]; then
    echo "   ❌ longhorn-manager 崩溃循环"
    echo "   需要先修复 manager:"
    echo "     1. 查看日志: kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo "     2. 如果是 iscsi 问题，安装 open-iscsi（见问题 1）"
    echo "     3. 重启 manager: kubectl delete pod -n longhorn-system -l app=longhorn-manager"
else
    echo "   ⚠️  longhorn-manager 状态: $MANAGER_STATUS"
    echo "   等待 manager 就绪..."
    echo "   如果长时间未就绪，检查日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
fi

echo ""
echo "=== 完成 ==="

