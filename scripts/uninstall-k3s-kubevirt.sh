#!/bin/bash

# 完全卸载 k3s 和 KubeVirt

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
echo_info "完全卸载 k3s 和 KubeVirt"
echo_info "=========================================="
echo ""
echo_warn "⚠️  这将删除："
echo "  - k3s 集群"
echo "  - KubeVirt"
echo "  - CDI"
echo "  - 所有 Kubernetes 资源"
echo "  - k3s 数据目录"
echo ""
read -p "确认卸载？(y/n，默认n): " CONFIRM
CONFIRM=${CONFIRM:-n}
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo_info "已取消"
    exit 0
fi

# ==========================================
# 步骤 1: 卸载 KubeVirt
# ==========================================
echo ""
echo_info "1. 卸载 KubeVirt"
echo ""

# 先删除 webhook 配置（避免 webhook 错误）
echo_info "  删除 ValidatingWebhookConfiguration..."
kubectl delete validatingwebhookconfiguration kubevirt-validator --ignore-not-found=true --wait=false 2>/dev/null || true
kubectl delete validatingwebhookconfiguration virt-api-validator --ignore-not-found=true --wait=false 2>/dev/null || true

echo_info "  删除 MutatingWebhookConfiguration..."
kubectl delete mutatingwebhookconfiguration kubevirt-mutator --ignore-not-found=true --wait=false 2>/dev/null || true
kubectl delete mutatingwebhookconfiguration virt-api-mutator --ignore-not-found=true --wait=false 2>/dev/null || true

# 删除所有 KubeVirt 相关的 webhook
kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep kubevirt | xargs -r kubectl delete --ignore-not-found=true --wait=false 2>/dev/null || true
kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep kubevirt | xargs -r kubectl delete --ignore-not-found=true --wait=false 2>/dev/null || true

sleep 3

# 现在删除 KubeVirt CR
if kubectl get kubevirt -n kubevirt kubevirt &>/dev/null; then
    echo_info "  删除 KubeVirt CR..."
    kubectl delete kubevirt -n kubevirt kubevirt --ignore-not-found=true --wait=false || {
        echo_warn "  删除失败，尝试强制删除..."
        kubectl patch kubevirt -n kubevirt kubevirt --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete kubevirt -n kubevirt kubevirt --ignore-not-found=true --wait=false || true
    }
    sleep 5
fi

# 删除 KubeVirt 命名空间
if kubectl get namespace kubevirt &>/dev/null; then
    echo_info "  删除 KubeVirt 命名空间..."
    kubectl delete namespace kubevirt --ignore-not-found=true --wait=false || {
        echo_warn "  删除失败，尝试强制删除..."
        kubectl patch namespace kubevirt --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete namespace kubevirt --ignore-not-found=true --wait=false --grace-period=0 || true
    }
fi

# ==========================================
# 步骤 2: 卸载 CDI
# ==========================================
echo ""
echo_info "2. 卸载 CDI"
echo ""

# 删除 CDI webhook 配置
kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep cdi | xargs -r kubectl delete --ignore-not-found=true --wait=false 2>/dev/null || true
kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep cdi | xargs -r kubectl delete --ignore-not-found=true --wait=false 2>/dev/null || true

sleep 2

# 删除 CDI CR
if kubectl get cdi -n cdi cdi &>/dev/null; then
    echo_info "  删除 CDI CR..."
    kubectl delete cdi -n cdi cdi --ignore-not-found=true --wait=false || {
        echo_warn "  删除失败，尝试强制删除..."
        kubectl patch cdi -n cdi cdi --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete cdi -n cdi cdi --ignore-not-found=true --wait=false || true
    }
    sleep 5
fi

# 删除 CDI 命名空间
if kubectl get namespace cdi &>/dev/null; then
    echo_info "  删除 CDI 命名空间..."
    kubectl delete namespace cdi --ignore-not-found=true --wait=false || {
        echo_warn "  删除失败，尝试强制删除..."
        kubectl patch namespace cdi --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        kubectl delete namespace cdi --ignore-not-found=true --wait=false --grace-period=0 || true
    }
fi

# ==========================================
# 步骤 3: 卸载 Rook/Ceph（如果存在）
# ==========================================
echo ""
echo_info "3. 卸载 Rook/Ceph"
echo ""

if kubectl get namespace rook-ceph &>/dev/null; then
    echo_info "  删除 Rook/Ceph..."
    kubectl delete namespace rook-ceph --ignore-not-found=true --wait=false
fi

# ==========================================
# 步骤 4: 卸载 Multus（如果存在）
# ==========================================
echo ""
echo_info "4. 卸载 Multus"
echo ""

if kubectl get daemonset -n kube-system kube-multus-ds &>/dev/null; then
    echo_info "  删除 Multus DaemonSet..."
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
fi

# ==========================================
# 步骤 5: 停止 k3s
# ==========================================
echo ""
echo_info "5. 停止 k3s"
echo ""

if sudo systemctl is-active --quiet k3s; then
    echo_info "  停止 k3s 服务..."
    sudo systemctl stop k3s
    echo_info "  ✓ k3s 已停止"
else
    echo_info "  k3s 未运行"
fi

# ==========================================
# 步骤 6: 卸载 k3s
# ==========================================
echo ""
echo_info "6. 卸载 k3s"
echo ""

if command -v k3s-uninstall.sh &>/dev/null; then
    echo_info "  使用 k3s 卸载脚本..."
    sudo /usr/local/bin/k3s-uninstall.sh || sudo /usr/local/bin/k3s-agent-uninstall.sh || echo_warn "  卸载脚本不存在"
else
    echo_warn "  k3s 卸载脚本不存在，手动清理..."
    
    # 手动清理
    echo_info "  删除 k3s 服务..."
    sudo systemctl disable k3s --now 2>/dev/null || true
    sudo rm -f /etc/systemd/system/k3s.service
    sudo rm -f /etc/systemd/system/k3s-agent.service
    sudo systemctl daemon-reload
    
    echo_info "  删除 k3s 二进制..."
    sudo rm -f /usr/local/bin/k3s
    sudo rm -f /usr/local/bin/k3s-agent
    sudo rm -f /usr/local/bin/k3s-killall.sh
    sudo rm -f /usr/local/bin/k3s-uninstall.sh
    sudo rm -f /usr/local/bin/k3s-agent-uninstall.sh
fi

# ==========================================
# 步骤 7: 清理 k3s 数据目录（可选）
# ==========================================
echo ""
echo_warn "7. 清理 k3s 数据目录（可选）"
echo ""

read -p "是否删除 k3s 数据目录？(y/n，默认n): " DELETE_DATA
DELETE_DATA=${DELETE_DATA:-n}

if [[ $DELETE_DATA =~ ^[Yy]$ ]]; then
    echo_warn "  ⚠️  删除 k3s 数据目录..."
    sudo rm -rf /var/lib/rancher/k3s
    sudo rm -rf /etc/rancher/k3s
    echo_info "  ✓ 数据目录已删除"
else
    echo_info "  保留数据目录（可以稍后手动删除）"
    echo_warn "  数据目录位置:"
    echo "    /var/lib/rancher/k3s"
    echo "    /etc/rancher/k3s"
fi

# ==========================================
# 步骤 8: 清理 CNI 配置（可选）
# ==========================================
echo ""
echo_warn "8. 清理 CNI 配置（可选）"
echo ""

read -p "是否删除 CNI 配置？(y/n，默认n): " DELETE_CNI
DELETE_CNI=${DELETE_CNI:-n}

if [[ $DELETE_CNI =~ ^[Yy]$ ]]; then
    echo_warn "  ⚠️  删除 CNI 配置..."
    sudo rm -rf /var/lib/rancher/k3s/agent/etc/cni
    sudo rm -rf /etc/cni
    echo_info "  ✓ CNI 配置已删除"
else
    echo_info "  保留 CNI 配置"
fi

# ==========================================
# 步骤 9: 清理 iptables 规则（可选）
# ==========================================
echo ""
echo_warn "9. 清理网络规则（可选）"
echo ""

read -p "是否清理 iptables 规则？(y/n，默认n): " CLEAN_IPTABLES
CLEAN_IPTABLES=${CLEAN_IPTABLES:-n}

if [[ $CLEAN_IPTABLES =~ ^[Yy]$ ]]; then
    echo_warn "  ⚠️  清理 iptables 规则..."
    sudo iptables -F
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    echo_info "  ✓ iptables 规则已清理"
else
    echo_info "  保留网络规则"
fi

echo ""
echo_info "=========================================="
echo_info "卸载完成"
echo_info "=========================================="
echo ""
echo_info "现在可以重新安装 k3s 和 KubeVirt:"
echo "  sudo ./scripts/reinstall-k3s-kubevirt.sh"
echo ""

