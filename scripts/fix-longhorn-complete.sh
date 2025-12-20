#!/bin/bash

# 完整修复 Longhorn 安装问题

set -e

echo "=== 完整修复 Longhorn ==="
echo ""

# 1. 检查当前状态
echo "1. 检查当前状态..."
./scripts/check-longhorn-status.sh
echo ""

# 2. 检查 longhorn-manager
echo "2. 检查 longhorn-manager..."
MANAGER_READY=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$MANAGER_READY" -eq 0 ]; then
    echo "⚠️  longhorn-manager 未就绪"
    echo ""
    echo "检查 manager 日志..."
    MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$MANAGER_POD" ]; then
        echo "最近的错误:"
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=5 2>&1 | grep -i "error\|fatal\|iscsi" || kubectl logs -n longhorn-system "$MANAGER_POD" --tail=5
    fi
    echo ""
    echo "如果错误包含 'iscsiadm' 或 'open-iscsi':"
    echo "  需要在所有节点上安装 open-iscsi"
    echo "  运行: ./scripts/install-open-iscsi.sh (在每个节点上)"
    echo ""
    read -p "是否已安装 open-iscsi？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "请先在所有节点上安装 open-iscsi，然后重新运行此脚本"
        exit 1
    fi
    
    echo ""
    echo "重启 longhorn-manager..."
    kubectl delete pod -n longhorn-system -l app=longhorn-manager
    echo "等待 manager 就绪..."
    sleep 10
else
    echo "✓ longhorn-manager 已就绪"
fi
echo ""

# 3. 等待 manager 就绪
echo "3. 等待 longhorn-manager 就绪..."
MAX_WAIT=300
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $MAX_WAIT ]; do
    READY=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$READY" -gt 0 ] && [ "$READY" -eq "$TOTAL" ]; then
        echo "✓ longhorn-manager 已就绪"
        break
    fi
    
    echo "  [$(date +%H:%M:%S)] 等待中... ($READY/$TOTAL)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时，请检查 manager 状态"
    kubectl get pods -n longhorn-system -l app=longhorn-manager
    exit 1
fi

# 4. 检查 driver-deployer
echo ""
echo "4. 检查 longhorn-driver-deployer..."
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    DEPLOYER_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "$DEPLOYER_STATUS" = "Running" ]; then
        echo "✓ longhorn-driver-deployer 已就绪"
    elif [ "$DEPLOYER_STATUS" = "Pending" ] || [ "$DEPLOYER_STATUS" = "PodInitializing" ]; then
        echo "⚠️  driver-deployer 仍在等待或初始化中"
        echo "   这通常是因为 manager 刚就绪，稍等片刻..."
        echo ""
        echo "   如果长时间卡住，可以重启:"
        echo "   kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
    else
        echo "⚠️  driver-deployer 状态: $DEPLOYER_STATUS"
    fi
else
    echo "未找到 driver-deployer Pod"
fi
echo ""

# 5. 最终状态
echo "5. 最终状态:"
kubectl get pods -n longhorn-system
echo ""

# 6. 检查 StorageClass
echo "6. 检查 StorageClass..."
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
echo "=== 修复完成 ==="
echo ""
echo "如果所有 Pods 都是 Running，Longhorn 已就绪！"
echo "验证: kubectl get pods -n longhorn-system"

