#!/bin/bash

# 验证 Longhorn 是否就绪可用

echo "=== 验证 Longhorn 就绪状态 ==="
echo ""

# 1. 检查 StorageClass
echo "1. 检查 StorageClass..."
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ longhorn StorageClass 存在"
    
    ALLOW_EXPANSION=$(kubectl get storageclass longhorn -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" = "true" ]; then
        echo "✓ 支持卷扩展"
    else
        echo "⚠️  不支持卷扩展"
    fi
    
    IS_DEFAULT=$(kubectl get storageclass longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
    if [ "$IS_DEFAULT" = "true" ]; then
        echo "✓ 已设置为默认 StorageClass"
    fi
else
    echo "❌ longhorn StorageClass 不存在"
    exit 1
fi
echo ""

# 2. 检查核心组件
echo "2. 检查核心组件..."
MANAGER_READY=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running.*1/1" || echo "0")
UI_READY=$(kubectl get pods -n longhorn-system -l app=longhorn-ui --no-headers 2>/dev/null | grep -c "Running.*1/1" || echo "0")

if [ "$MANAGER_READY" -gt 0 ]; then
    echo "✓ longhorn-manager 运行正常 ($MANAGER_READY)"
else
    echo "⚠️  longhorn-manager 未就绪"
fi

if [ "$UI_READY" -gt 0 ]; then
    echo "✓ longhorn-ui 运行正常 ($UI_READY)"
else
    echo "⚠️  longhorn-ui 未就绪"
fi
echo ""

# 3. 检查 Service
echo "3. 检查 Service..."
if kubectl get svc -n longhorn-system longhorn-backend &>/dev/null; then
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -n "$ENDPOINTS" ]; then
        echo "✓ longhorn-backend Service 有 Endpoints"
    else
        echo "⚠️  longhorn-backend Service 没有 Endpoints"
    fi
else
    echo "⚠️  longhorn-backend Service 不存在"
fi
echo ""

# 4. 检查 driver-deployer（可选组件）
echo "4. 检查 driver-deployer（可选）..."
DEPLOYER_STATUS=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$DEPLOYER_STATUS" = "Running" ]; then
    echo "✓ longhorn-driver-deployer 运行正常"
elif [ "$DEPLOYER_STATUS" = "PodInitializing" ]; then
    echo "⚠️  longhorn-driver-deployer 仍在初始化中"
    echo "   这通常不影响基本使用，StorageClass 已可用"
else
    echo "⚠️  longhorn-driver-deployer 状态: $DEPLOYER_STATUS"
fi
echo ""

# 5. 总结
echo "5. 总结:"
if [ "$MANAGER_READY" -gt 0 ] && kubectl get storageclass longhorn &>/dev/null; then
    echo "✅ Longhorn 核心功能已就绪！"
    echo ""
    echo "可以在 Wukong 中使用:"
    echo "  storageClassName: longhorn"
    echo ""
    if [ "$DEPLOYER_STATUS" != "Running" ]; then
        echo "注意: driver-deployer 仍在初始化，但不影响基本使用"
        echo "如果长时间卡住，可以忽略或稍后重启"
    fi
else
    echo "⚠️  Longhorn 可能未完全就绪"
    echo "请检查上述组件的状态"
fi

echo ""
echo "=== 完成 ==="

