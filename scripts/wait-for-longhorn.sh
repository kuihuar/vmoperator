#!/bin/bash

# 等待 Longhorn 就绪并自动修复

set -e

echo "=== 等待 Longhorn 就绪 ==="

# 1. 检查 longhorn-manager 状态
echo "1. 检查 longhorn-manager 状态..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$MANAGER_POD" ]; then
    echo "❌ 未找到 longhorn-manager Pod"
    exit 1
fi

MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
echo "Manager Pod: $MANAGER_POD"
echo "状态: $MANAGER_STATUS"
echo ""

# 2. 如果 manager 不是 Running，检查原因
if [ "$MANAGER_STATUS" != "Running" ]; then
    echo "⚠️  longhorn-manager 未就绪，检查日志..."
    kubectl logs -n longhorn-system "$MANAGER_POD" --tail=20 2>&1 | tail -10
    echo ""
    
    # 检查是否是 iscsi 问题
    if kubectl logs -n longhorn-system "$MANAGER_POD" --tail=50 2>&1 | grep -qi "iscsiadm\|open-iscsi"; then
        echo "❌ 检测到 iscsi 问题"
        echo "需要在所有节点上安装 open-iscsi:"
        echo "  sudo apt-get update && sudo apt-get install -y open-iscsi"
        echo "  sudo systemctl enable iscsid && sudo systemctl start iscsid"
        echo ""
        echo "安装完成后，重启 manager:"
        echo "  kubectl delete pod -n longhorn-system -l app=longhorn-manager"
        exit 1
    fi
    
    echo "等待 manager 就绪..."
    MAX_WAIT=300
    ELAPSED=0
    INTERVAL=5
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$STATUS" = "Running" ]; then
            echo "✓ longhorn-manager 已就绪"
            break
        fi
        echo "  [$(date +%H:%M:%S)] 等待中... ($STATUS)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "⚠️  等待超时，请检查 manager 状态"
        kubectl get pods -n longhorn-system -l app=longhorn-manager
        exit 1
    fi
else
    echo "✓ longhorn-manager 已就绪"
fi

# 3. 等待 driver-deployer
echo ""
echo "2. 等待 longhorn-driver-deployer..."
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$DEPLOYER_POD" ]; then
    echo "未找到 driver-deployer Pod"
    exit 1
fi

echo "Driver Deployer Pod: $DEPLOYER_POD"
echo "等待 Init Container 完成..."

MAX_WAIT=300
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    READY=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    
    if [ "$STATUS" = "Running" ] && [ "$READY" = "true" ]; then
        echo "✓ longhorn-driver-deployer 已就绪"
        break
    fi
    
    # 显示 Init Container 状态
    INIT_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null || echo "waiting")
    echo "  [$(date +%H:%M:%S)] 等待中... ($STATUS, Init: $INIT_STATUS)"
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时"
    echo ""
    echo "如果 manager 已就绪但 driver-deployer 仍卡住，可以重启:"
    echo "  kubectl delete pod -n longhorn-system $DEPLOYER_POD"
    exit 1
fi

# 4. 最终状态
echo ""
echo "3. 最终状态:"
kubectl get pods -n longhorn-system
echo ""

# 5. 检查 StorageClass
echo "4. 检查 StorageClass..."
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ longhorn StorageClass 存在"
    ALLOW_EXPANSION=$(kubectl get storageclass longhorn -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" = "true" ]; then
        echo "✓ 支持卷扩展"
    fi
else
    echo "⚠️  longhorn StorageClass 不存在（可能需要等待）"
fi

echo ""
echo "=== 完成 ==="
echo ""
echo "Longhorn 已就绪！可以在 Wukong 中使用:"
echo "  storageClassName: longhorn"

