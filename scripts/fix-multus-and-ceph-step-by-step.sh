#!/bin/bash

# 完整修复步骤：先恢复基础设施，再配置 Multus

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
echo_info "完整修复步骤：恢复基础设施 + 配置 Multus"
echo_info "=========================================="
echo ""
echo_warn "⚠️  这个脚本会："
echo "  1. 临时禁用 Multus 作为默认 CNI（恢复基础设施）"
echo "  2. 重启 k3s 让配置生效"
echo "  3. 验证 Ceph 等基础设施恢复正常"
echo "  4. 后续再配置 Multus 作为 secondary CNI（仅用于 VM）"
echo ""
read -p "继续执行？(y/n，默认y): " CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo_info "已取消"
    exit 0
fi

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# ==========================================
# 步骤 1: 备份并临时禁用 Multus 配置
# ==========================================
echo ""
echo_step "步骤 1: 备份并临时禁用 Multus 配置"
echo ""

if [ -f "$MULTUS_CONF" ]; then
    BACKUP_FILE="$MULTUS_CONF.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp "$MULTUS_CONF" "$BACKUP_FILE"
    echo_info "  ✓ 已备份到: $BACKUP_FILE"
    
    # 重命名，让 k3s 不再读取
    sudo mv "$MULTUS_CONF" "$MULTUS_CONF.disabled"
    echo_info "  ✓ 已禁用 Multus 配置（重命名为 .disabled）"
else
    echo_warn "  ⚠️  Multus 配置文件不存在，可能已经禁用"
fi

# ==========================================
# 步骤 2: 重启 k3s 让配置生效
# ==========================================
echo ""
echo_step "步骤 2: 重启 k3s 让配置生效"
echo ""

echo_warn "  ⚠️  即将重启 k3s，这会导致短暂的集群中断"
read -p "确认重启 k3s？(y/n，默认y): " RESTART
RESTART=${RESTART:-y}

if [[ $RESTART =~ ^[Yy]$ ]]; then
    echo_info "  重启 k3s..."
    sudo systemctl restart k3s
    
    echo_info "  等待 k3s 启动（约 30 秒）..."
    sleep 30
    
    # 检查 k3s 状态
    if sudo systemctl is-active --quiet k3s; then
        echo_info "  ✓ k3s 已启动"
    else
        echo_error "  ✗ k3s 启动失败，请检查: sudo systemctl status k3s"
        exit 1
    fi
else
    echo_warn "  ⚠️  跳过重启，请手动执行: sudo systemctl restart k3s"
fi

# ==========================================
# 步骤 3: 验证集群状态
# ==========================================
echo ""
echo_step "步骤 3: 验证集群状态"
echo ""

echo_info "  等待集群就绪..."
sleep 10

# 检查节点
echo_info "  检查节点状态:"
kubectl get nodes

# 检查系统 Pods
echo ""
echo_info "  检查系统 Pods:"
kubectl get pods -n kube-system | head -10

# ==========================================
# 步骤 4: 检查 Ceph/Rook Operator
# ==========================================
echo ""
echo_step "步骤 4: 检查 Ceph/Rook Operator"
echo ""

if kubectl get namespace rook-ceph &>/dev/null; then
    echo_info "  检查 Rook Operator Pods:"
    kubectl get pods -n rook-ceph
    
    # 如果有旧的 Pod 在 CrashLoopBackOff，删除让它们重建
    FAILED_PODS=$(kubectl get pods -n rook-ceph --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$FAILED_PODS" ]; then
        echo_warn "  发现失败的 Pods，删除让它们重建..."
        for pod in $FAILED_PODS; do
            kubectl delete pod -n rook-ceph $pod --force --grace-period=0 2>/dev/null || true
        done
        echo_info "  ✓ 已删除失败的 Pods"
    fi
else
    echo_info "  rook-ceph 命名空间不存在，稍后可以重新安装"
fi

# ==========================================
# 步骤 5: 验证网络是否正常
# ==========================================
echo ""
echo_step "步骤 5: 验证网络是否正常"
echo ""

echo_info "  检查 CNI 配置:"
sudo ls -la "$CNI_CONF_DIR"/*.conf* 2>/dev/null | head -5

echo ""
echo_info "  检查是否有网络错误:"
# 检查最近创建的 Pod 是否有网络错误
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason? | contains("CreatePodSandbox") or contains("Network")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -5 || echo "  未发现明显的网络错误"

# ==========================================
# 总结
# ==========================================
echo ""
echo_info "=========================================="
echo_info "步骤 1-5 完成"
echo_info "=========================================="
echo ""
echo_info "当前状态:"
echo "  - Multus 配置已临时禁用（.disabled）"
echo "  - k3s 已重启，使用默认 CNI（flannel）"
echo "  - 基础设施 Pods 应该能正常启动"
echo ""
echo_warn "下一步（可选）:"
echo "  1. 等待所有 Pods 恢复正常（约 2-5 分钟）"
echo "  2. 验证 Ceph 安装: kubectl get pods -n rook-ceph"
echo "  3. 如果需要 Multus（仅用于 VM），可以："
echo "     - 恢复 Multus 配置但配置为 secondary CNI"
echo "     - 或参考文档重新配置 Multus"
echo ""
echo_info "检查命令:"
echo "  kubectl get pods -A"
echo "  kubectl get pods -n rook-ceph"
echo "  kubectl get pods -n kube-system"
echo ""

