#!/bin/bash

# 快速修复 Multus kubeconfig（一行命令）

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
KUBECONFIG_FILE="$CNI_DIR/multus.d/multus.kubeconfig"

echo "创建 Multus kubeconfig 文件..."

sudo mkdir -p "$CNI_DIR/multus.d"

if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    sudo cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_FILE"
    sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$KUBECONFIG_FILE"
    sudo chmod 644 "$KUBECONFIG_FILE"
    echo "✓ kubeconfig 已创建: $KUBECONFIG_FILE"
    sudo ls -la "$KUBECONFIG_FILE"
else
    echo "✗ 未找到 /etc/rancher/k3s/k3s.yaml"
    exit 1
fi

