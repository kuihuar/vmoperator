#!/bin/bash

# 安装 Longhorn 存储（推荐用于 k3s 生产环境）

set -e

echo "=== 安装 Longhorn 存储 ==="

# 1. 检查 k3s 环境
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装"
    exit 1
fi

echo "✓ kubectl 已安装"
echo ""

# 2. 检查集群状态
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到 Kubernetes 集群"
    exit 1
fi

echo "✓ 集群连接正常"
echo ""

# 3. 安装 Longhorn
echo "1. 安装 Longhorn..."
LONGHORN_VERSION="v1.6.0"
echo "使用版本: $LONGHORN_VERSION"

kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml

echo "✓ Longhorn 安装完成"
echo ""

# 4. 等待 Longhorn 就绪
echo "2. 等待 Longhorn 就绪..."
echo "（这可能需要几分钟）"

MAX_WAIT=600  # 最多等待 10 分钟
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    READY_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$READY_PODS" -gt 0 ] && [ "$READY_PODS" -eq "$TOTAL_PODS" ]; then
        echo "✓ Longhorn Manager 已就绪"
        break
    fi
    
    echo "  [$(date +%H:%M:%S)] 等待中... ($READY_PODS/$TOTAL_PODS pods ready)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时，请检查 Longhorn 状态:"
    echo "  kubectl get pods -n longhorn-system"
    exit 1
fi

# 5. 验证 StorageClass
echo ""
echo "3. 验证 StorageClass..."

sleep 5  # 等待 StorageClass 创建

if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ Longhorn StorageClass 已创建"
    
    # 检查是否支持扩展
    ALLOW_EXPANSION=$(kubectl get storageclass longhorn -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" = "true" ]; then
        echo "✓ 支持卷扩展"
    else
        echo "⚠️  不支持卷扩展（可能需要手动配置）"
    fi
    
    # 检查是否为默认 StorageClass
    IS_DEFAULT=$(kubectl get storageclass longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
    if [ "$IS_DEFAULT" = "true" ]; then
        echo "✓ 已设置为默认 StorageClass"
    else
        echo "ℹ️  未设置为默认 StorageClass"
        echo "  可以在 Wukong 中明确指定: storageClassName: longhorn"
    fi
else
    echo "⚠️  Longhorn StorageClass 未找到，等待创建..."
    sleep 10
    if kubectl get storageclass longhorn &>/dev/null; then
        echo "✓ Longhorn StorageClass 已创建"
    else
        echo "❌ Longhorn StorageClass 创建失败"
        echo "请检查: kubectl get storageclass"
    fi
fi

# 6. 显示状态
echo ""
echo "4. Longhorn 组件状态:"
kubectl get pods -n longhorn-system

echo ""
echo "5. StorageClass 列表:"
kubectl get storageclass

echo ""
echo "=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 在 Wukong 中使用 Longhorn StorageClass:"
echo "     storageClassName: longhorn"
echo ""
echo "  2. 访问 Longhorn UI（如果需要）:"
echo "     kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo "     然后访问: http://localhost:8080"
echo ""
echo "  3. 查看 Longhorn 状态:"
echo "     kubectl get pods -n longhorn-system"
echo "     kubectl get storageclass longhorn"

