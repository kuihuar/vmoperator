#!/bin/bash

# 修复 driver-deployer Init:0/1 问题

set -e

echo "=== 修复 driver-deployer Init:0/1 问题 ==="
echo ""

# 1. 检查 driver-deployer
echo "1. 检查 driver-deployer..."
DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$DRIVER_DEPLOYER" ]; then
    echo "❌ driver-deployer Pod 不存在"
    exit 1
fi

STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.phase}' 2>/dev/null)
echo "Pod: $DRIVER_DEPLOYER"
echo "状态: $STATUS"
echo ""

# 2. 检查 longhorn-backend
echo "2. 检查 longhorn-backend..."
if ! kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    echo "❌ longhorn-backend Service 不存在"
    echo "请先确保 Longhorn Manager 已安装"
    exit 1
fi

ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
if [ -z "$ENDPOINTS" ]; then
    echo "❌ longhorn-backend 没有 Endpoints"
    echo ""
    echo "检查 Manager Pods..."
    kubectl get pods -n longhorn-system -l app=longhorn-manager
    echo ""
    
    # 检查 Manager 状态
    MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    RUNNING_MANAGERS=0
    
    if [ -n "$MANAGER_PODS" ]; then
        for mgr in $MANAGER_PODS; do
            MGR_STATUS=$(kubectl get pod -n longhorn-system "$mgr" -o jsonpath='{.status.phase}' 2>/dev/null)
            if [ "$MGR_STATUS" = "Running" ]; then
                RUNNING_MANAGERS=$((RUNNING_MANAGERS + 1))
            fi
        done
    fi
    
    if [ $RUNNING_MANAGERS -eq 0 ]; then
        echo "❌ 没有运行中的 Manager Pods"
        echo ""
        echo "解决方案:"
        echo "  1. 检查 Manager 日志:"
        echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
        echo ""
        echo "  2. 如果 Manager 有问题，修复后重启:"
        echo "     kubectl delete pod -n longhorn-system -l app=longhorn-manager"
        echo ""
        echo "  3. 等待 Manager 就绪后，Endpoints 会自动创建"
        exit 1
    else
        echo "✓ 有 $RUNNING_MANAGERS 个运行中的 Manager Pods"
        echo "但 Endpoints 仍未创建，可能原因:"
        echo "  1. Manager 刚启动，需要更多时间"
        echo "  2. Manager 无法绑定 9500 端口"
        echo ""
        echo "等待 Endpoints 创建..."
        for i in {1..60}; do
            ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
            if [ -n "$ENDPOINTS" ]; then
                echo "✓ Endpoints 已创建: $ENDPOINTS"
                break
            fi
            echo "  等待中... ($i/60)"
            sleep 2
        done
        
        if [ -z "$ENDPOINTS" ]; then
            echo "⚠️  等待超时，Endpoints 仍未创建"
            echo "检查 Manager 是否监听 9500 端口:"
            FIRST_MANAGER=$(echo $MANAGER_PODS | awk '{print $1}')
            kubectl exec -n longhorn-system "$FIRST_MANAGER" -- netstat -tlnp 2>/dev/null | grep 9500 || \
            kubectl exec -n longhorn-system "$FIRST_MANAGER" -- ss -tlnp 2>/dev/null | grep 9500 || \
            echo "  无法检查（可能需要更多权限）"
            echo ""
            echo "查看 Manager 日志:"
            kubectl logs -n longhorn-system "$FIRST_MANAGER" --tail=30 | grep -iE "listen|9500|error" | tail -10
        fi
    fi
else
    echo "✓ longhorn-backend 有 Endpoints: $ENDPOINTS"
fi
echo ""

# 3. 如果 Endpoints 存在，重启 driver-deployer
if [ -n "$ENDPOINTS" ]; then
    echo "3. Endpoints 已存在，重启 driver-deployer..."
    echo "删除 driver-deployer Pod..."
    kubectl delete pod -n longhorn-system "$DRIVER_DEPLOYER" --ignore-not-found=true
    
    echo "等待新 Pod 创建..."
    sleep 5
    
    # 等待新 Pod
    for i in {1..30}; do
        NEW_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$NEW_POD" ] && [ "$NEW_POD" != "$DRIVER_DEPLOYER" ]; then
            echo "✓ 新 Pod 已创建: $NEW_POD"
            DRIVER_DEPLOYER="$NEW_POD"
            break
        fi
        echo "  等待中... ($i/30)"
        sleep 2
    done
    
    if [ -z "$NEW_POD" ] || [ "$NEW_POD" = "$DRIVER_DEPLOYER" ]; then
        echo "⚠️  新 Pod 可能未创建，检查:"
        kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer
    fi
    echo ""
    
    # 4. 监控新 Pod 状态
    echo "4. 监控 driver-deployer 状态..."
    echo "（这可能需要几分钟）"
    echo ""
    
    for i in {1..120}; do
        CURRENT_STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$CURRENT_STATUS" = "Succeeded" ]; then
            echo "✓ driver-deployer 已完成！"
            break
        elif [ "$CURRENT_STATUS" = "Running" ]; then
            echo "  driver-deployer 正在运行... ($i/120)"
        elif [ "$CURRENT_STATUS" = "Failed" ] || [ "$CURRENT_STATUS" = "Error" ]; then
            echo "❌ driver-deployer 失败"
            echo "查看日志:"
            kubectl logs -n longhorn-system "$DRIVER_DEPLOYER" --all-containers=true --tail=20
            exit 1
        else
            INIT_STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null)
            echo "  等待中... ($i/120) - 状态: $CURRENT_STATUS, Init: $INIT_STATUS"
        fi
        
        sleep 2
    done
    
    # 5. 最终检查
    echo ""
    echo "5. 最终检查..."
    FINAL_STATUS=$(kubectl get pod -n longhorn-system "$DRIVER_DEPLOYER" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$FINAL_STATUS" = "Succeeded" ]; then
        echo "✓ driver-deployer 成功完成"
        echo ""
        echo "检查 CSI Driver:"
        kubectl get csidriver driver.longhorn.io 2>/dev/null && echo "✓ CSI Driver 已安装" || echo "⚠️  CSI Driver 可能还在安装中"
    else
        echo "⚠️  driver-deployer 状态: $FINAL_STATUS"
        echo ""
        echo "查看详细日志:"
        kubectl logs -n longhorn-system "$DRIVER_DEPLOYER" --all-containers=true --tail=30
    fi
else
    echo "3. Endpoints 不存在，无法继续"
    echo ""
    echo "请先解决 Manager 问题，然后重新运行此脚本"
fi

echo ""
echo "=== 完成 ==="

