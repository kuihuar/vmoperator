#!/bin/bash

# 检查 Longhorn 版本和兼容性

echo "=== 检查 Longhorn 版本和兼容性 ==="
echo ""

# 1. 检查当前安装的版本
echo "1. 检查 Longhorn 版本..."
LONGHORN_IMAGES=$(kubectl get pods -n longhorn-system -o jsonpath='{.items[*].spec.containers[*].image}' 2>/dev/null | tr ' ' '\n' | grep longhornio | sort -u)

if [ -n "$LONGHORN_IMAGES" ]; then
    echo "Longhorn 镜像版本:"
    echo "$LONGHORN_IMAGES" | while read img; do
        VERSION=$(echo "$img" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "未知")
        echo "  - $img (版本: $VERSION)"
    done
else
    echo "⚠️  无法获取 Longhorn 镜像信息"
fi
echo ""

# 2. 检查 Kubernetes 版本
echo "2. 检查 Kubernetes 版本..."
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}' || kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' | sed 's/v//')
echo "Kubernetes 版本: $K8S_VERSION"
echo ""

# 3. 检查 k3s 版本（如果是 k3s）
echo "3. 检查 k3s 版本（如果适用）..."
if command -v k3s &> /dev/null; then
    K3S_VERSION=$(k3s --version 2>/dev/null | head -1)
    echo "$K3S_VERSION"
elif kubectl get nodes -o jsonpath='{.items[0].nodeInfo.kubeletVersion}' 2>/dev/null | grep -q "k3s"; then
    K3S_VERSION=$(kubectl get nodes -o jsonpath='{.items[0].nodeInfo.kubeletVersion}' 2>/dev/null)
    echo "k3s 版本: $K3S_VERSION"
fi
echo ""

# 4. 检查 driver-deployer 状态
echo "4. 检查 driver-deployer 状态..."
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    DEPLOYER_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    RESTARTS=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    AGE=$(kubectl get pod -n longhorn-system "$DEPLOYER_POD" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
    
    echo "Pod: $DEPLOYER_POD"
    echo "状态: $DEPLOYER_STATUS"
    echo "重启次数: $RESTARTS"
    echo "创建时间: $AGE"
    
    if [ "$DEPLOYER_STATUS" = "PodInitializing" ]; then
        echo ""
        echo "Init Container 日志（最后 20 行）:"
        kubectl logs -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager --tail=20 2>&1 | tail -10
    fi
else
    echo "未找到 driver-deployer Pod"
fi
echo ""

# 5. 检查 manager API
echo "5. 检查 manager API 状态..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    echo "Manager Pod: $MANAGER_POD"
    
    # 检查是否监听 9500 端口
    if kubectl exec -n longhorn-system "$MANAGER_POD" -- netstat -tlnp 2>/dev/null | grep -q "9500"; then
        echo "✓ Manager 正在监听 9500 端口"
    else
        echo "❌ Manager 未监听 9500 端口"
        echo "检查 manager 日志..."
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=30 2>&1 | grep -i -E "api|server|listen|9500|error" | tail -10
    fi
fi
echo ""

# 6. 检查 StorageClass
echo "6. 检查 StorageClass..."
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ longhorn StorageClass 存在"
    PROVISIONER=$(kubectl get storageclass longhorn -o jsonpath='{.provisioner}' 2>/dev/null)
    echo "Provisioner: $PROVISIONER"
else
    echo "❌ longhorn StorageClass 不存在"
fi
echo ""

# 7. 版本兼容性建议
echo "7. 版本兼容性建议:"
echo ""
echo "Longhorn v1.6.0 兼容性:"
echo "  - Kubernetes: 1.21+"
echo "  - k3s: 1.21+"
echo ""
echo "如果遇到 driver-deployer 问题:"
echo "  1. 检查 Kubernetes/k3s 版本是否兼容"
echo "  2. 检查 manager API 是否正常启动"
echo "  3. 如果 StorageClass 已存在，可以忽略 driver-deployer 状态"
echo ""

# 8. 提供解决方案
echo "8. 解决方案:"
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✅ StorageClass 已存在，Longhorn 基本功能可用"
    echo ""
    echo "选项 1: 忽略 driver-deployer（推荐）"
    echo "  - StorageClass 已创建，可以正常使用"
    echo "  - driver-deployer 是可选组件"
    echo ""
    echo "选项 2: 尝试修复"
    echo "  - 检查 manager API 是否正常"
    echo "  - 等待更长时间（可能需要 10-15 分钟）"
    echo "  - 或尝试降级/升级 Longhorn 版本"
else
    echo "⚠️  StorageClass 不存在，需要等待 driver-deployer 完成"
fi

echo ""
echo "=== 完成 ==="

