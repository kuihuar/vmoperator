#!/bin/bash

# 检查 Rook Operator Pod 的错误

echo "检查 Rook Operator Pod 错误..."
echo ""

POD_NAME=$(kubectl get pods -n rook-ceph -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo "未找到 Rook Operator Pod"
    exit 1
fi

echo "Pod: $POD_NAME"
echo ""

# 1. Pod 状态
echo "=== 1. Pod 状态 ==="
kubectl get pod -n rook-ceph $POD_NAME
echo ""

# 2. Pod 事件（最近 20 条）
echo "=== 2. Pod 事件 ==="
kubectl describe pod -n rook-ceph $POD_NAME | grep -A 30 "Events:"
echo ""

# 3. 检查是否是网络问题
echo "=== 3. 检查网络相关错误 ==="
kubectl describe pod -n rook-ceph $POD_NAME 2>&1 | grep -i "network\|multus\|sandbox\|cni" || echo "未发现明显的网络错误"
echo ""

# 4. 检查容器状态
echo "=== 4. 容器状态 ==="
kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.status.containerStatuses[*].state}' | jq '.' 2>/dev/null || kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.status.containerStatuses[*].state}'
echo ""

# 5. 检查 Multus 配置是否真的被禁用
echo "=== 5. 检查 Multus 配置 ==="
if [ -f /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf ]; then
    echo "⚠️  Multus 配置仍然存在（未被禁用）"
    sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
else
    echo "✓ Multus 配置已禁用"
    sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf* 2>/dev/null || echo "未找到 Multus 配置文件"
fi
echo ""

# 6. 检查 k3s 是否重启过
echo "=== 6. 检查 k3s 运行时间 ==="
sudo systemctl status k3s --no-pager | grep -E "Active:|since" | head -2
echo ""

