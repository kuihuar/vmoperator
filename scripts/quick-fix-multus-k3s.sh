#!/bin/bash

# 快速修复 Multus 在 k3s 中的配置

echo "=== 快速修复 Multus 在 k3s 中的配置 ==="

# 1. 检查 k3s CNI 配置路径
echo -e "\n1. 检查 k3s CNI 配置路径..."
K3S_CNI_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if [ -d "$K3S_CNI_PATH" ]; then
    echo "✓ k3s CNI 配置路径存在: $K3S_CNI_PATH"
    echo "配置文件:"
    sudo ls -la "$K3S_CNI_PATH" | head -5
else
    echo "❌ k3s CNI 配置路径不存在"
    exit 1
fi

# 2. 备份 Multus DaemonSet
echo -e "\n2. 备份 Multus DaemonSet..."
kubectl get daemonset -n kube-system kube-multus-ds -o yaml > /tmp/multus-ds-backup-$(date +%Y%m%d-%H%M%S).yaml
echo "✓ 已备份"

# 3. 更新 Multus DaemonSet
echo -e "\n3. 更新 Multus DaemonSet..."
kubectl patch daemonset -n kube-system kube-multus-ds --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes/0/hostPath/path",
    "value": "/var/lib/rancher/k3s/agent/etc/cni/net.d"
  }
]' 2>&1

if [ $? -eq 0 ]; then
    echo "✓ 已更新 CNI 配置路径"
else
    echo "⚠️  更新失败，尝试完整更新..."
    # 如果简单 patch 失败，需要完整更新
    echo "请手动编辑: kubectl edit daemonset -n kube-system kube-multus-ds"
    echo "将 volumes[0].hostPath.path 改为: /var/lib/rancher/k3s/agent/etc/cni/net.d"
    exit 1
fi

# 4. 删除 Pod 触发重启
echo -e "\n4. 删除 Pod 触发重启..."
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo "等待 Pod 重启..."
sleep 15

# 5. 检查状态
echo -e "\n5. 检查状态..."
kubectl get pods -n kube-system -l app=multus

echo ""
echo "检查日志（应该没有错误）:"
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MULTUS_POD" ]; then
    kubectl logs -n kube-system "$MULTUS_POD" --tail=20 | grep -E "error|failed|Found primary CNI|multus-daemon started" || kubectl logs -n kube-system "$MULTUS_POD" --tail=10
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果仍然有错误，检查："
echo "  1. k3s CNI 路径: sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/"
echo "  2. Multus Pod 日志: kubectl logs -n kube-system -l app=multus"
echo "  3. 手动编辑: kubectl edit daemonset -n kube-system kube-multus-ds"

