#!/bin/bash

# 修复 Multus CNI 插件的 kubeconfig 路径问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复 Multus CNI 插件 kubeconfig 路径"
echo_info "=========================================="
echo ""

# 关键发现：Multus CNI 插件在主机上运行，不是在 Pod 内运行
# 配置文件中的路径 `/host/etc/cni/net.d/multus.d/multus.kubeconfig` 是 Pod 内的路径
# 但 CNI 插件在主机上运行，需要主机路径

MULTUS_CONF="/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf"
CURRENT_KUBECONFIG_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig' 2>/dev/null || echo "")

echo_info "当前配置的 kubeconfig 路径: $CURRENT_KUBECONFIG_PATH"
echo ""

# 如果路径是 /host/etc/cni/net.d/...，这是 Pod 内路径，CNI 插件在主机上无法访问
if [[ "$CURRENT_KUBECONFIG_PATH" == /host/* ]]; then
    echo_warn "问题：配置中的路径是 Pod 内路径，但 CNI 插件在主机上运行"
    echo_info "修复：改为主机路径"
    
    # 去掉 /host 前缀，得到主机路径
    HOST_PATH="${CURRENT_KUBECONFIG_PATH#/host}"
    HOST_FULL_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
    
    echo_info "新的主机路径: $HOST_FULL_PATH"
    
    # 备份配置
    sudo cp "$MULTUS_CONF" "${MULTUS_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # 更新配置
    sudo cat "$MULTUS_CONF" | jq ".kubeconfig = \"$HOST_FULL_PATH\"" | sudo tee "${MULTUS_CONF}.tmp" > /dev/null
    sudo mv "${MULTUS_CONF}.tmp" "$MULTUS_CONF"
    sudo chmod 644 "$MULTUS_CONF"
    
    echo_info "✓ 配置文件已更新"
else
    echo_info "路径看起来是主机路径，检查文件是否存在..."
    if [ -f "$CURRENT_KUBECONFIG_PATH" ]; then
        echo_info "✓ 文件存在: $CURRENT_KUBECONFIG_PATH"
    else
        echo_error "✗ 文件不存在: $CURRENT_KUBECONFIG_PATH"
        echo_info "尝试使用标准路径..."
        HOST_FULL_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
        if [ -f "$HOST_FULL_PATH" ]; then
            echo_info "找到文件，更新配置..."
            sudo cp "$MULTUS_CONF" "${MULTUS_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
            sudo cat "$MULTUS_CONF" | jq ".kubeconfig = \"$HOST_FULL_PATH\"" | sudo tee "${MULTUS_CONF}.tmp" > /dev/null
            sudo mv "${MULTUS_CONF}.tmp" "$MULTUS_CONF"
            sudo chmod 644 "$MULTUS_CONF"
            echo_info "✓ 配置文件已更新"
        fi
    fi
fi

echo ""
echo_info "验证配置:"
sudo cat "$MULTUS_CONF" | jq '.kubeconfig'

echo ""
echo_info "验证文件:"
KUBECONFIG_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig')
if [ -f "$KUBECONFIG_PATH" ]; then
    echo_info "✓ 文件存在: $KUBECONFIG_PATH"
    sudo ls -lh "$KUBECONFIG_PATH"
else
    echo_error "✗ 文件不存在: $KUBECONFIG_PATH"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "重要：CNI 插件在主机上运行，配置文件中的路径必须是主机绝对路径"
echo_info "如果仍无法工作，可能需要重启 kubelet 或节点"
echo ""

