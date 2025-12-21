#!/bin/bash

# 立即修复 Multus kubeconfig - 最简单直接的方法

set -e

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
KUBECONFIG_FILE="$CNI_DIR/multus.d/multus.kubeconfig"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

echo "=========================================="
echo "修复 Multus kubeconfig 文件"
echo "=========================================="
echo ""

# 1. 创建目录
echo "1. 创建目录..."
sudo mkdir -p "$CNI_DIR/multus.d"
echo "✓ 目录已创建: $CNI_DIR/multus.d"

# 2. 检查 k3s kubeconfig
if [ ! -f "$K3S_KUBECONFIG" ]; then
    echo "✗ 错误：未找到 k3s kubeconfig: $K3S_KUBECONFIG"
    exit 1
fi

# 3. 复制并修改 kubeconfig
echo ""
echo "2. 创建 multus.kubeconfig..."
sudo cp "$K3S_KUBECONFIG" "$KUBECONFIG_FILE"

# 修改 server 地址
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$KUBECONFIG_FILE"

# 设置权限
sudo chmod 644 "$KUBECONFIG_FILE"

echo "✓ 文件已创建: $KUBECONFIG_FILE"

# 4. 验证文件
echo ""
echo "3. 验证文件..."
if [ -f "$KUBECONFIG_FILE" ]; then
    echo "✓ 文件存在"
    echo ""
    echo "文件信息:"
    sudo ls -lh "$KUBECONFIG_FILE"
    echo ""
    echo "文件内容预览:"
    sudo head -5 "$KUBECONFIG_FILE"
    echo ""
    echo "✓ 验证通过"
else
    echo "✗ 文件创建失败"
    exit 1
fi

# 5. 检查 Pod 内是否能访问（通过 Multus Pod）
echo ""
echo "4. 检查 Pod 内访问（如果 Multus Pod 存在）..."
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo "Multus Pod: $MULTUS_POD"
    if kubectl exec -n kube-system $MULTUS_POD -- test -f /etc/cni/net.d/multus.d/multus.kubeconfig 2>/dev/null; then
        echo "✓ Pod 内可以访问文件"
    else
        echo "⚠ Pod 内无法访问（可能需要检查挂载）"
    fi
fi

echo ""
echo "=========================================="
echo "修复完成！"
echo "=========================================="
echo ""
echo "现在可以重启受影响的 Pod："
echo "  kubectl delete pod -n rook-ceph rook-ceph-operator-84f6b7f9fb-ld7st"
echo ""
echo "或删除所有 Rook Pod 让其自动恢复："
echo "  kubectl delete pods -n rook-ceph --all"
echo ""

