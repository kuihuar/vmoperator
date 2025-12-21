#!/bin/bash

# 修复 CSI Driver 未安装问题

set -e

echo "=== 修复 CSI Driver 未安装问题 ==="
echo ""

# 1. 检查 CSI Driver
echo "1. 检查 CSI Driver..."
if kubectl get csidriver driver.longhorn.io &>/dev/null; then
    echo "✓ CSI Driver 已安装"
    exit 0
fi
echo "❌ CSI Driver 未安装"
echo ""

# 2. 检查 longhorn-driver-deployer
echo "2. 检查 longhorn-driver-deployer..."
DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o name 2>/dev/null | head -1)
if [ -z "$DRIVER_DEPLOYER" ]; then
    echo "❌ longhorn-driver-deployer Pod 不存在"
    echo "可能 Longhorn 安装不完整"
    exit 1
fi

DEPLOYER_NAME=$(echo $DRIVER_DEPLOYER | cut -d'/' -f2)
DEPLOYER_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
echo "Driver Deployer: $DEPLOYER_NAME"
echo "状态: $DEPLOYER_STATUS"
echo ""

# 3. 检查 Init Containers
if [ "$DEPLOYER_STATUS" != "Running" ] && [ "$DEPLOYER_STATUS" != "Succeeded" ]; then
    echo "3. 检查 Init Containers..."
    INIT_COUNT=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
    if [ "$INIT_COUNT" -gt 0 ]; then
        echo "Init Containers ($INIT_COUNT 个):"
        for init in $(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null); do
            INIT_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath="{.status.initContainerStatuses[?(@.name=='$init')].ready}" 2>/dev/null)
            INIT_STATE=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath="{.status.initContainerStatuses[?(@.name=='$init')].state}" 2>/dev/null)
            echo "  $init: Ready=$INIT_STATUS, State=$INIT_STATE"
            
            if [ "$INIT_STATUS" != "true" ]; then
                echo "    查看日志:"
                kubectl logs -n longhorn-system "$DEPLOYER_NAME" -c "$init" --tail=10 2>&1 | sed 's/^/      /'
            fi
        done
    fi
    echo ""
fi

# 4. 检查 longhorn-backend
echo "4. 检查 longhorn-backend Service..."
if kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    BACKEND_ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [ -n "$BACKEND_ENDPOINTS" ]; then
        echo "✓ longhorn-backend 有端点: $BACKEND_ENDPOINTS"
    else
        echo "⚠️  longhorn-backend 没有端点"
    fi
else
    echo "⚠️  longhorn-backend Service 不存在"
fi
echo ""

# 5. 检查 longhorn-manager
echo "5. 检查 longhorn-manager..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Manager Pod: $MANAGER_POD"
    echo "状态: $MANAGER_STATUS"
    
    if [ "$MANAGER_STATUS" != "Running" ]; then
        echo "❌ Manager 未运行，这是问题所在"
        echo "查看日志:"
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=20 2>&1 | tail -10
        exit 1
    fi
else
    echo "❌ Manager Pod 不存在"
    exit 1
fi
echo ""

# 6. 解决方案
echo "6. 解决方案..."
echo ""

if [ "$DEPLOYER_STATUS" = "Pending" ] || [ "$DEPLOYER_STATUS" = "Init:0/1" ] || [ "$DEPLOYER_STATUS" = "Init:CrashLoopBackOff" ]; then
    echo "Driver Deployer 未完成，尝试修复..."
    echo ""
    
    # 检查是否是等待 longhorn-backend
    if [ "$DEPLOYER_STATUS" = "Init:0/1" ]; then
        echo "Driver Deployer 在等待 longhorn-backend API..."
        echo "等待 Manager 完全就绪..."
        
        # 等待 Manager API 可用
        for i in {1..30}; do
            if kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | grep -q "."; then
                echo "✓ longhorn-backend API 可用"
                break
            fi
            echo "  等待中... ($i/30)"
            sleep 2
        done
    fi
    
    # 重启 driver-deployer
    echo ""
    echo "重启 driver-deployer..."
    kubectl delete pod -n longhorn-system "$DEPLOYER_NAME" --ignore-not-found=true
    
    echo "等待 driver-deployer 重新创建..."
    sleep 5
    
    # 等待新 Pod 创建
    for i in {1..30}; do
        NEW_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$NEW_DEPLOYER" ]; then
            echo "✓ 新 Pod 已创建: $NEW_DEPLOYER"
            break
        fi
        echo "  等待中... ($i/30)"
        sleep 2
    done
    
    echo ""
    echo "监控 driver-deployer 状态..."
    echo "（这可能需要几分钟）"
    
    for i in {1..60}; do
        CURRENT_STATUS=$(kubectl get pod -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [ "$CURRENT_STATUS" = "Succeeded" ]; then
            echo "✓ driver-deployer 已完成"
            break
        elif [ "$CURRENT_STATUS" = "Running" ]; then
            echo "  driver-deployer 正在运行... ($i/60)"
        else
            echo "  等待中... ($i/60) - 状态: $CURRENT_STATUS"
        fi
        sleep 2
    done
    
elif [ "$DEPLOYER_STATUS" = "Succeeded" ]; then
    echo "✓ driver-deployer 已完成"
    echo "但 CSI Driver 仍未安装，可能需要等待或手动检查"
    
else
    echo "Driver Deployer 状态: $DEPLOYER_STATUS"
    echo "查看日志以了解问题:"
    kubectl logs -n longhorn-system "$DEPLOYER_NAME" --all-containers=true --tail=20 2>&1 | tail -15
fi
echo ""

# 7. 验证 CSI Driver
echo "7. 验证 CSI Driver..."
sleep 5

if kubectl get csidriver driver.longhorn.io &>/dev/null; then
    echo "✓ CSI Driver 已安装"
    echo ""
    echo "CSI Driver 信息:"
    kubectl get csidriver driver.longhorn.io -o yaml | grep -E "name|provisioner" | head -5
else
    echo "⚠️  CSI Driver 仍未安装"
    echo ""
    echo "可能原因:"
    echo "  1. driver-deployer 仍在运行中（等待完成）"
    echo "  2. driver-deployer 失败（查看日志）"
    echo ""
    echo "检查:"
    echo "  kubectl get pods -n longhorn-system | grep driver-deployer"
    echo "  kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true"
fi
echo ""

# 8. 检查 CSI 组件
echo "8. 检查 CSI 组件..."
CSI_COMPONENTS=("longhorn-csi-attacher" "longhorn-csi-provisioner" "longhorn-csi-resizer" "longhorn-csi-plugin")
ALL_RUNNING=true

for component in "${CSI_COMPONENTS[@]}"; do
    if kubectl get deployment -n longhorn-system "$component" &>/dev/null; then
        READY=$(kubectl get deployment -n longhorn-system "$component" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment -n longhorn-system "$component" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
            echo "  ✓ $component: $READY/$DESIRED ready"
        else
            echo "  ⚠️  $component: $READY/$DESIRED ready"
            ALL_RUNNING=false
        fi
    elif kubectl get daemonset -n longhorn-system "$component" &>/dev/null; then
        READY=$(kubectl get daemonset -n longhorn-system "$component" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get daemonset -n longhorn-system "$component" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
            echo "  ✓ $component: $READY/$DESIRED ready"
        else
            echo "  ⚠️  $component: $READY/$DESIRED ready"
            ALL_RUNNING=false
        fi
    else
        echo "  ❌ $component: 不存在"
        ALL_RUNNING=false
    fi
done
echo ""

if [ "$ALL_RUNNING" = true ]; then
    echo "✓ 所有 CSI 组件运行正常"
else
    echo "⚠️  部分 CSI 组件未就绪"
fi
echo ""

echo "=== 修复完成 ==="
echo ""
echo "如果 CSI Driver 仍未安装，请:"
echo "  1. 检查 driver-deployer 日志:"
echo "     kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true"
echo ""
echo "  2. 检查 longhorn-manager 日志:"
echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
echo ""
echo "  3. 等待几分钟，让系统完成初始化"
echo ""

