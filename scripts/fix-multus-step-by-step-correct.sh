#!/bin/bash

# 正确的修复步骤

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复步骤：恢复基础设施"
echo_info "=========================================="
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# ==========================================
# 步骤 1: 检查并备份 Multus 配置
# ==========================================
echo_step "步骤 1: 检查并备份 Multus 配置"
echo ""

if [ -f "$MULTUS_CONF" ]; then
    echo_info "  找到 Multus 配置文件"
    BACKUP_FILE="$MULTUS_CONF.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp "$MULTUS_CONF" "$BACKUP_FILE"
    echo_info "  ✓ 已备份到: $BACKUP_FILE"
    
    # 禁用 Multus 配置
    sudo mv "$MULTUS_CONF" "$MULTUS_CONF.disabled"
    echo_info "  ✓ 已禁用 Multus 配置"
else
    echo_warn "  ⚠️  Multus 配置文件不存在: $MULTUS_CONF"
    echo_info "  检查是否有 .disabled 文件:"
    sudo ls -la "$CNI_CONF_DIR"/00-multus.conf* 2>/dev/null || echo "  未找到相关文件"
    
    # 检查是否已经禁用
    if sudo ls -1 "$CNI_CONF_DIR"/00-multus.conf.disabled 2>/dev/null | grep -q .; then
        echo_info "  ✓ Multus 配置已经禁用"
    else
        echo_warn "  ⚠️  Multus 配置可能已经被删除或不存在"
    fi
fi

echo ""

# ==========================================
# 步骤 2: 检查当前 CNI 配置
# ==========================================
echo_step "步骤 2: 检查当前 CNI 配置"
echo ""

echo_info "  CNI 配置目录内容:"
sudo ls -la "$CNI_CONF_DIR"/*.{conf,conflist} 2>/dev/null | head -10 || echo "  未找到配置文件"

echo ""

# ==========================================
# 步骤 3: 重启 k3s
# ==========================================
echo_step "步骤 3: 重启 k3s（可选）"
echo ""

echo_warn "  ⚠️  如果 Multus 配置已禁用，需要重启 k3s 让配置生效"
read -p "是否重启 k3s？(y/n，默认y): " RESTART
RESTART=${RESTART:-y}

if [[ $RESTART =~ ^[Yy]$ ]]; then
    echo_info "  重启 k3s..."
    sudo systemctl restart k3s
    
    echo_info "  等待 k3s 启动（约 30 秒）..."
    sleep 30
    
    if sudo systemctl is-active --quiet k3s; then
        echo_info "  ✓ k3s 已启动"
    else
        echo_error "  ✗ k3s 启动失败"
        sudo systemctl status k3s --no-pager | head -10
        exit 1
    fi
else
    echo_warn "  ⚠️  跳过重启，请稍后手动执行: sudo systemctl restart k3s"
fi

echo ""

# ==========================================
# 步骤 4: 验证集群状态
# ==========================================
echo_step "步骤 4: 验证集群状态"
echo ""

echo_info "  等待集群就绪..."
sleep 10

echo_info "  节点状态:"
kubectl get nodes

echo ""
echo_info "  系统 Pods 状态:"
kubectl get pods -n kube-system | head -10

echo ""

# ==========================================
# 步骤 5: 检查 Rook Operator
# ==========================================
echo_step "步骤 5: 检查 Rook Operator"
echo ""

if kubectl get namespace rook-ceph &>/dev/null; then
    echo_info "  Rook Operator Pods:"
    kubectl get pods -n rook-ceph
    
    # 删除失败的 Pods
    FAILED_PODS=$(kubectl get pods -n rook-ceph --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$FAILED_PODS" ]; then
        echo ""
        echo_warn "  删除失败的 Pods 让它们重建..."
        for pod in $FAILED_PODS; do
            kubectl delete pod -n rook-ceph "$pod" --force --grace-period=0 2>/dev/null || true
        done
        echo_info "  ✓ 已删除失败的 Pods"
    fi
else
    echo_info "  rook-ceph 命名空间不存在"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "检查命令:"
echo "  kubectl get pods -A"
echo "  kubectl get pods -n rook-ceph"
echo ""

