#!/bin/bash

# 直接创建 kubeconfig 文件，不管现有配置如何

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "直接创建 Multus kubeconfig 文件"
echo ""

# 根据错误信息，路径是 /host/etc/cni/net.d/multus.d/multus.kubeconfig
# 对应主机路径应该是 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

HOST_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

echo_info "目标文件: $HOST_FILE"
echo ""

# 检查 k3s kubeconfig
if [ ! -f "$K3S_KUBECONFIG" ]; then
    echo_error "k3s kubeconfig 不存在: $K3S_KUBECONFIG"
    exit 1
fi

# 创建目录
echo_info "创建目录..."
sudo mkdir -p "$(dirname "$HOST_FILE")"

# 复制文件
echo_info "复制 kubeconfig..."
sudo cp "$K3S_KUBECONFIG" "$HOST_FILE"

# 修改 server 地址
echo_info "修改 server 地址..."
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$HOST_FILE"

# 设置权限
echo_info "设置权限..."
sudo chmod 644 "$HOST_FILE"

# 验证
echo ""
echo_info "验证文件:"
sudo ls -lh "$HOST_FILE"

echo ""
echo_info "完成！"
echo_info "文件已创建: $HOST_FILE"
echo ""
echo_info "现在重启受影响的 Pod:"
echo "  kubectl delete pods -n rook-ceph --all --force --grace-period=0"
echo ""

