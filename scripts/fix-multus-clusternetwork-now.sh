#!/bin/bash

# 快速修复 Multus clusterNetwork 配置

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "快速修复 Multus clusterNetwork"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# 1. 查找 k3s 实际使用的 CNI
echo_info "1. 查找 k3s 默认 CNI 名称"
echo ""

# 先检查 .conflist 文件（k3s 常用）
DEFAULT_CNI_NAME=""
if sudo ls -1 "$CNI_CONF_DIR"/*.conflist 2>/dev/null | grep -q .; then
    FIRST_CONFLIST=$(sudo ls -1 "$CNI_CONF_DIR"/*.conflist 2>/dev/null | head -1)
    DEFAULT_CNI_NAME=$(sudo cat "$FIRST_CONFLIST" | jq -r '.plugins[0].name // .name // ""' 2>/dev/null || echo "")
    if [ -n "$DEFAULT_CNI_NAME" ]; then
        echo_info "  找到 CNI 名称: $DEFAULT_CNI_NAME"
        echo_info "  来自文件: $FIRST_CONFLIST"
    fi
fi

# 如果还没找到，检查 .conf 文件
if [ -z "$DEFAULT_CNI_NAME" ]; then
    DEFAULT_CNI_CONF=$(sudo ls -1 "$CNI_CONF_DIR"/*.conf 2>/dev/null | grep -v multus | head -1 || echo "")
    if [ -n "$DEFAULT_CNI_CONF" ]; then
        DEFAULT_CNI_NAME=$(sudo cat "$DEFAULT_CNI_CONF" | jq -r '.name // ""' 2>/dev/null || echo "")
        if [ -n "$DEFAULT_CNI_NAME" ]; then
            echo_info "  找到 CNI 名称: $DEFAULT_CNI_NAME"
        fi
    fi
fi

# 如果还是没找到，使用 k3s 默认值
if [ -z "$DEFAULT_CNI_NAME" ]; then
    echo_warn "  未找到 CNI 配置，使用 k3s 默认值: flannel"
    DEFAULT_CNI_NAME="flannel"
fi

echo ""

# 2. 检查当前配置
echo_info "2. 检查当前配置"
echo ""

CURRENT_VALUE=$(sudo cat "$MULTUS_CONF" | jq -r '.clusterNetwork // ""' 2>/dev/null || echo "")
echo_info "  当前 clusterNetwork: $CURRENT_VALUE"
echo_info "  应该改为: $DEFAULT_CNI_NAME"
echo ""

if [ "$CURRENT_VALUE" = "$DEFAULT_CNI_NAME" ]; then
    echo_info "  ✓ 配置已经是正确值，无需修改"
    exit 0
fi

# 3. 备份并修复
echo_info "3. 修复配置"
echo ""

# 备份
BACKUP_FILE="$MULTUS_CONF.backup.$(date +%Y%m%d-%H%M%S)"
sudo cp "$MULTUS_CONF" "$BACKUP_FILE"
echo_info "  ✓ 已备份到: $BACKUP_FILE"

# 使用 jq 修复（如果可用）
if command -v jq &> /dev/null; then
    CURRENT_JSON=$(sudo cat "$MULTUS_CONF" | jq '.')
    echo "$CURRENT_JSON" | jq ".clusterNetwork = \"$DEFAULT_CNI_NAME\"" | sudo tee "$MULTUS_CONF" > /dev/null
    echo_info "  ✓ 已使用 jq 修复"
else
    # 使用 sed 修复
    sudo sed -i "s|\"clusterNetwork\":\s*\"[^\"]*\"|\"clusterNetwork\": \"$DEFAULT_CNI_NAME\"|g" "$MULTUS_CONF"
    echo_info "  ✓ 已使用 sed 修复"
fi

# 4. 验证
echo ""
echo_info "4. 验证修复结果"
echo ""

NEW_VALUE=$(sudo cat "$MULTUS_CONF" | jq -r '.clusterNetwork // ""' 2>/dev/null || echo "")
if [ "$NEW_VALUE" = "$DEFAULT_CNI_NAME" ]; then
    echo_info "  ✓ 修复成功: $NEW_VALUE"
else
    echo_error "  ✗ 修复失败，当前值: $NEW_VALUE"
    echo_info "  回滚: sudo cp $BACKUP_FILE $MULTUS_CONF"
    exit 1
fi

echo ""
echo_info "5. 重启 Multus Pod"
echo ""

kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo_info "  ✓ Pod 已删除，等待重新创建..."
sleep 5
kubectl get pods -n kube-system -l app=multus

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "现在可以检查 Rook Operator Pod:"
echo "  kubectl get pods -n rook-ceph"
echo ""

