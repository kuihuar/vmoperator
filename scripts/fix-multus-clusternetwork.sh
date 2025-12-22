#!/bin/bash

# 修复 Multus clusterNetwork 配置问题

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
echo_info "修复 Multus clusterNetwork 配置"
echo_info "=========================================="
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# 1. 检查当前 Multus 配置
echo_info "1. 检查当前 Multus 配置"
echo ""

if [ ! -f "$MULTUS_CONF" ]; then
    echo_error "  ✗ Multus 配置文件不存在: $MULTUS_CONF"
    exit 1
fi

echo_info "  当前配置:"
sudo cat "$MULTUS_CONF" | jq '.' 2>/dev/null || sudo cat "$MULTUS_CONF"
echo ""

# 2. 查找 k3s 实际使用的默认 CNI
echo_info "2. 查找 k3s 默认 CNI"
echo ""

# 查找第一个非 multus 的 CNI 配置文件
DEFAULT_CNI_CONF=$(sudo ls -1 "$CNI_CONF_DIR"/*.conf 2>/dev/null | grep -v multus | head -1 || echo "")
DEFAULT_CNI_NAME=""

if [ -n "$DEFAULT_CNI_CONF" ]; then
    echo_info "  找到默认 CNI 配置: $DEFAULT_CNI_CONF"
    DEFAULT_CNI_NAME=$(sudo cat "$DEFAULT_CNI_CONF" | jq -r '.name // ""' 2>/dev/null || echo "")
    
    if [ -z "$DEFAULT_CNI_NAME" ]; then
        # 尝试从文件名推断
        DEFAULT_CNI_NAME=$(basename "$DEFAULT_CNI_CONF" .conf)
    fi
    
    echo_info "  默认 CNI 名称: $DEFAULT_CNI_NAME"
else
    echo_warn "  ⚠️  未找到默认 CNI 配置，尝试常见名称..."
    # k3s 常见使用 flannel
    DEFAULT_CNI_NAME="flannel"
fi

# 3. 修复 Multus 配置
echo ""
echo_info "3. 修复 Multus 配置"
echo ""

# 检查是否需要修改
CURRENT_CLUSTER_NETWORK=$(sudo cat "$MULTUS_CONF" | jq -r '.clusterNetwork // ""' 2>/dev/null || echo "")
if [ "$CURRENT_CLUSTER_NETWORK" = "$DEFAULT_CNI_NAME" ]; then
    echo_info "  ✓ clusterNetwork 已经是正确值: $DEFAULT_CNI_NAME"
    echo_info "  ✓ 无需修改"
    exit 0
fi

echo_warn "  将修改 clusterNetwork:"
echo_detail "    从: $CURRENT_CLUSTER_NETWORK"
echo_detail "    到: $DEFAULT_CNI_NAME"
echo ""

# 询问确认
read -p "确认修改？(y/n，默认n): " CONFIRM
CONFIRM=${CONFIRM:-n}
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo_info "  已取消修改"
    exit 0
fi

# 备份原配置
BACKUP_FILE="$MULTUS_CONF.backup.$(date +%Y%m%d-%H%M%S)"
sudo cp "$MULTUS_CONF" "$BACKUP_FILE"
echo_info "  ✓ 已备份原配置到: $BACKUP_FILE"
echo_info "  如需回滚: sudo cp $BACKUP_FILE $MULTUS_CONF"

# 读取当前配置并修改
CURRENT_CONF=$(sudo cat "$MULTUS_CONF" | jq '.' 2>/dev/null || echo "{}")

# 使用 jq 修改 clusterNetwork
if command -v jq &> /dev/null; then
    echo_info "  使用 jq 修改配置..."
    echo "$CURRENT_CONF" | jq ".clusterNetwork = \"$DEFAULT_CNI_NAME\"" | sudo tee "$MULTUS_CONF" > /dev/null
else
    echo_warn "  jq 未安装，使用 sed 修改..."
    # 使用 sed 修改（更简单但不够精确）
    sudo sed -i "s|\"clusterNetwork\":\s*\"[^\"]*\"|\"clusterNetwork\": \"$DEFAULT_CNI_NAME\"|g" "$MULTUS_CONF"
fi

echo_info "  ✓ 配置已更新"
echo ""

# 4. 验证新配置
echo_info "4. 验证新配置"
echo ""
echo_info "  新配置:"
sudo cat "$MULTUS_CONF" | jq '.' 2>/dev/null || sudo cat "$MULTUS_CONF"
echo ""

# 5. 重启 Multus Pod（如果需要）
echo_info "5. 重启 Multus Pod 应用新配置"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  删除 Multus Pod 以应用新配置..."
    kubectl delete pod -n kube-system $MULTUS_POD --force --grace-period=0 2>/dev/null || true
    echo_info "  ✓ Pod 已删除，等待重新创建..."
    sleep 5
    kubectl get pods -n kube-system -l app=multus
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "现在可以重新尝试创建 Rook Operator Pod"
echo "  检查: kubectl get pods -n rook-ceph"
echo ""

