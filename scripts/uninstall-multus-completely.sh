#!/bin/bash

# 完全卸载 Multus，恢复 k3s 默认网络

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
echo_info "完全卸载 Multus CNI"
echo_info "=========================================="
echo ""
echo_warn "⚠️  这将："
echo "  1. 删除 Multus DaemonSet"
echo "  2. 删除 Multus 配置文件"
echo "  3. 删除 Multus 二进制文件"
echo "  4. 恢复 k3s 默认 CNI（flannel）"
echo ""
read -p "确认卸载 Multus？(y/n，默认y): " CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo_info "已取消"
    exit 0
fi

# ==========================================
# 步骤 1: 删除 Multus DaemonSet
# ==========================================
echo ""
echo_step "步骤 1: 删除 Multus DaemonSet"
echo ""

if kubectl get daemonset -n kube-system kube-multus-ds &>/dev/null; then
    echo_info "  删除 Multus DaemonSet..."
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
    echo_info "  ✓ DaemonSet 已删除"
    
    # 等待 Pods 删除
    echo_info "  等待 Pods 删除..."
    sleep 10
else
    echo_info "  Multus DaemonSet 不存在"
fi

# ==========================================
# 步骤 2: 删除 Multus 相关资源
# ==========================================
echo ""
echo_step "步骤 2: 删除 Multus 相关资源"
echo ""

# 删除 ServiceAccount
kubectl delete serviceaccount -n kube-system multus --ignore-not-found=true && echo_info "  ✓ ServiceAccount 已删除" || echo_info "  ServiceAccount 不存在"

# 删除 ClusterRole 和 ClusterRoleBinding
kubectl delete clusterrole multus --ignore-not-found=true && echo_info "  ✓ ClusterRole 已删除" || echo_info "  ClusterRole 不存在"
kubectl delete clusterrolebinding multus --ignore-not-found=true && echo_info "  ✓ ClusterRoleBinding 已删除" || echo_info "  ClusterRoleBinding 不存在"

# 删除 ConfigMap
kubectl delete configmap -n kube-system multus-cni-config --ignore-not-found=true && echo_info "  ✓ ConfigMap 已删除" || echo_info "  ConfigMap 不存在"

# ==========================================
# 步骤 3: 删除 Multus 配置文件
# ==========================================
echo ""
echo_step "步骤 3: 删除 Multus 配置文件"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"

# 备份并删除 Multus 配置文件
if [ -f "$CNI_CONF_DIR/00-multus.conf" ]; then
    BACKUP_FILE="$CNI_CONF_DIR/00-multus.conf.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp "$CNI_CONF_DIR/00-multus.conf" "$BACKUP_FILE"
    echo_info "  ✓ 已备份到: $BACKUP_FILE"
    sudo rm -f "$CNI_CONF_DIR/00-multus.conf"
    echo_info "  ✓ Multus 配置文件已删除"
else
    echo_info "  Multus 配置文件不存在"
fi

# 删除 Multus 配置目录（可选，保留 kubeconfig 备份）
if [ -d "$CNI_CONF_DIR/multus.d" ]; then
    echo_info "  保留 multus.d 目录（包含备份文件）"
    # sudo rm -rf "$CNI_CONF_DIR/multus.d"
fi

# 删除主机上的 Multus 配置文件（如果存在）
if [ -f "/etc/cni/net.d/00-multus.conf" ]; then
    sudo rm -f /etc/cni/net.d/00-multus.conf
    echo_info "  ✓ 主机 Multus 配置文件已删除"
fi

if [ -d "/etc/cni/net.d/multus.d" ]; then
    sudo rm -rf /etc/cni/net.d/multus.d
    echo_info "  ✓ 主机 Multus 配置目录已删除"
fi

# ==========================================
# 步骤 4: 删除 Multus 二进制文件（可选）
# ==========================================
echo ""
echo_step "步骤 4: 删除 Multus 二进制文件（可选）"
echo ""

read -p "是否删除 Multus 二进制文件？(y/n，默认n): " DELETE_BIN
DELETE_BIN=${DELETE_BIN:-n}

if [[ $DELETE_BIN =~ ^[Yy]$ ]]; then
    # k3s CNI 二进制目录
    if [ -f "/var/lib/rancher/k3s/data/current/bin/multus-shim" ]; then
        sudo rm -f /var/lib/rancher/k3s/data/current/bin/multus-shim
        echo_info "  ✓ multus-shim 已删除"
    fi
    
    if [ -f "/opt/cni/bin/multus" ]; then
        sudo rm -f /opt/cni/bin/multus
        echo_info "  ✓ multus 二进制已删除"
    fi
    
    if [ -f "/opt/cni/bin/multus-shim" ]; then
        sudo rm -f /opt/cni/bin/multus-shim
        echo_info "  ✓ multus-shim 已删除"
    fi
else
    echo_info "  保留二进制文件（可以稍后手动删除）"
fi

# ==========================================
# 步骤 5: 重启 k3s
# ==========================================
echo ""
echo_step "步骤 5: 重启 k3s 让配置生效"
echo ""

echo_warn "  ⚠️  即将重启 k3s，这会导致短暂的集群中断"
read -p "确认重启 k3s？(y/n，默认y): " RESTART
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
    echo_warn "  ⚠️  跳过重启，请手动执行: sudo systemctl restart k3s"
fi

# ==========================================
# 步骤 6: 验证
# ==========================================
echo ""
echo_step "步骤 6: 验证卸载结果"
echo ""

echo_info "  等待集群就绪..."
sleep 10

echo_info "  检查节点:"
kubectl get nodes

echo ""
echo_info "  检查 CNI 配置:"
sudo ls -la "$CNI_CONF_DIR"/*.{conf,conflist} 2>/dev/null | head -5 || echo "  未找到配置文件"

echo ""
echo_info "  检查系统 Pods:"
kubectl get pods -n kube-system | head -5

echo ""
echo_info "  检查是否还有 Multus Pods:"
kubectl get pods -n kube-system | grep multus || echo "  ✓ 没有 Multus Pods"

echo ""
echo_info "=========================================="
echo_info "Multus 卸载完成"
echo_info "=========================================="
echo ""
echo_info "现在集群使用 k3s 默认 CNI（flannel）"
echo_info "可以继续安装 Ceph:"
echo "  sudo ./scripts/install-ceph-rook.sh"
echo ""

