#!/bin/bash

# 最终修复 driver-deployer 问题

set -e

echo "=== 最终修复 driver-deployer ==="
echo ""

# 1. 检查当前状态
echo "1. 检查当前状态..."
./scripts/check-longhorn-version.sh
echo ""

# 2. 检查 StorageClass
echo "2. 检查 StorageClass..."
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✅ StorageClass 已存在"
    echo ""
    echo "重要: StorageClass 已创建，说明 Longhorn 核心功能已可用"
    echo "driver-deployer 是可选组件，可以忽略其状态"
    echo ""
    read -p "是否继续尝试修复 driver-deployer？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "选择忽略 driver-deployer，继续使用 Longhorn"
        exit 0
    fi
else
    echo "⚠️  StorageClass 不存在，需要修复 driver-deployer"
fi
echo ""

# 3. 检查 manager API
echo "3. 检查 manager API..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    echo "测试 manager API..."
    HTTP_CODE=$(kubectl exec -n longhorn-system "$MANAGER_POD" -- curl -m 3 -s -o /dev/null -w "%{http_code}" http://localhost:9500/v1 2>&1 || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Manager API 正常"
    else
        echo "⚠️  Manager API 不可访问（返回: $HTTP_CODE）"
        echo ""
        echo "检查 manager 日志..."
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=50 2>&1 | grep -i -E "api|server|listen|9500|started" | tail -10
        echo ""
        echo "可能的原因:"
        echo "  1. Manager API 服务未正常启动"
        echo "  2. 需要更多时间启动"
        echo "  3. 版本兼容性问题"
        echo ""
        read -p "是否重启 manager 并重试？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "重启 manager..."
            kubectl delete pod -n longhorn-system -l app=longhorn-manager
            echo "等待 manager 重启..."
            sleep 30
            kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s 2>/dev/null || true
        fi
    fi
fi
echo ""

# 4. 尝试修复 driver-deployer
echo "4. 尝试修复 driver-deployer..."

# 选项 1: 删除并等待重建
echo "选项 1: 删除 driver-deployer 并等待重建..."
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
echo "等待重建..."
sleep 10

# 等待最多 10 分钟
MAX_WAIT=600
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$DEPLOYER_POD" ]; then
        STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
        READY=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
        
        if [ "$STATUS" = "Running" ] && [ "$READY" = "true" ]; then
            echo "✓ driver-deployer 已就绪"
            break
        fi
        
        echo "  [$(date +%H:%M:%S)] 等待中... ($STATUS, Ready: $READY)"
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时"
    echo ""
    echo "如果 StorageClass 已存在，可以忽略 driver-deployer 状态"
    echo "Longhorn 基本功能仍然可用"
fi
echo ""

# 5. 最终状态
echo "5. 最终状态:"
kubectl get pods -n longhorn-system | grep -E "NAME|longhorn"
echo ""

if kubectl get storageclass longhorn &>/dev/null; then
    echo "✅ Longhorn 可以使用（StorageClass 已存在）"
    echo ""
    echo "可以在 Wukong 中使用:"
    echo "  storageClassName: longhorn"
else
    echo "⚠️  StorageClass 不存在，需要等待 driver-deployer 完成"
fi

echo ""
echo "=== 完成 ==="

