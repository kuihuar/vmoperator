#!/bin/bash

# 验证 Longhorn 安装和配置

echo "=== 验证 Longhorn 安装 ==="

# 1. 检查 Longhorn 命名空间
echo "1. 检查 Longhorn 命名空间..."
if kubectl get namespace longhorn-system &>/dev/null; then
    echo "✓ longhorn-system 命名空间存在"
else
    echo "❌ longhorn-system 命名空间不存在"
    echo "请先安装 Longhorn: ./scripts/setup-longhorn.sh"
    exit 1
fi

# 2. 检查 Longhorn Pods
echo ""
echo "2. 检查 Longhorn Pods..."
PODS=$(kubectl get pods -n longhorn-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_PODS=$(kubectl get pods -n longhorn-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$PODS" -gt 0 ]; then
    echo "  总 Pods: $PODS"
    echo "  运行中: $READY_PODS"
    if [ "$READY_PODS" -eq "$PODS" ]; then
        echo "✓ 所有 Pods 运行正常"
    else
        echo "⚠️  部分 Pods 未就绪"
        echo "  未就绪的 Pods:"
        kubectl get pods -n longhorn-system | grep -v "Running"
    fi
else
    echo "❌ 未找到 Longhorn Pods"
    exit 1
fi

# 3. 检查 StorageClass
echo ""
echo "3. 检查 StorageClass..."
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ longhorn StorageClass 存在"
    
    # 检查是否支持扩展
    ALLOW_EXPANSION=$(kubectl get storageclass longhorn -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" = "true" ]; then
        echo "✓ 支持卷扩展"
    else
        echo "⚠️  不支持卷扩展（可能需要配置）"
    fi
    
    # 检查是否为默认 StorageClass
    IS_DEFAULT=$(kubectl get storageclass longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
    if [ "$IS_DEFAULT" = "true" ]; then
        echo "✓ 已设置为默认 StorageClass"
    else
        echo "ℹ️  未设置为默认 StorageClass"
    fi
else
    echo "❌ longhorn StorageClass 不存在"
    exit 1
fi

# 4. 检查 Longhorn UI
echo ""
echo "4. 检查 Longhorn UI..."
if kubectl get svc -n longhorn-system longhorn-frontend &>/dev/null; then
    echo "✓ Longhorn UI Service 存在"
    echo "  访问方式: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
else
    echo "⚠️  Longhorn UI Service 不存在"
fi

# 5. 检查节点状态
echo ""
echo "5. 检查节点状态..."
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
echo "  总节点: $NODES"
echo "  就绪节点: $READY_NODES"

# 6. 检查现有 PVC
echo ""
echo "6. 检查使用 Longhorn 的 PVC..."
LONGHORN_PVCS=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName=="longhorn") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")
if [ -n "$LONGHORN_PVCS" ]; then
    echo "  找到以下 PVC:"
    echo "$LONGHORN_PVCS" | while read pvc; do
        echo "    - $pvc"
    done
else
    echo "  ℹ️  暂无使用 Longhorn 的 PVC"
fi

# 7. 总结
echo ""
echo "=== 验证完成 ==="
echo ""
echo "Longhorn 状态:"
if [ "$READY_PODS" -eq "$PODS" ] && [ "$PODS" -gt 0 ]; then
    echo "  ✅ Longhorn 安装正常"
else
    echo "  ⚠️  Longhorn 可能未完全就绪"
fi

echo ""
echo "下一步:"
echo "  1. 在 Wukong 中使用: storageClassName: longhorn"
echo "  2. 访问 UI: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo "  3. 查看文档: docs/LONGHORN_SETUP.md"

