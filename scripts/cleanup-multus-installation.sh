#!/bin/bash

# 清理当前的 Multus 安装和配置

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
echo_info "清理 Multus 安装和配置"
echo_info "=========================================="
echo ""

# 1. 删除 Multus DaemonSet
echo_info "1. 删除 Multus DaemonSet"
echo ""

if kubectl get daemonset -n kube-system kube-multus-ds > /dev/null 2>&1; then
    echo_info "  删除 DaemonSet..."
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
    echo_info "  ✓ DaemonSet 已删除"
    
    # 等待 Pod 终止
    echo_info "  等待 Pod 终止..."
    sleep 5
else
    echo_info "  DaemonSet 不存在，跳过"
fi

# 2. 删除 Multus Pods（如果有残留）
echo ""
echo_info "2. 删除 Multus Pods"
echo ""

MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_PODS" ]; then
    for pod in $MULTUS_PODS; do
        echo_info "  删除 Pod: $pod"
        kubectl delete $pod -n kube-system --force --grace-period=0 2>/dev/null || true
    done
    echo_info "  ✓ Pods 已删除"
else
    echo_info "  没有找到 Multus Pods"
fi

# 3. 删除配置文件
echo ""
echo_info "3. 删除配置文件"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"
DAEMON_CONFIG="$CNI_CONF_DIR/multus.d/daemon-config.json"
KUBECONFIG_FILE="$CNI_CONF_DIR/multus.d/multus.kubeconfig"

# 备份配置文件（可选）
BACKUP_DIR="/tmp/multus-backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

if [ -f "$MULTUS_CONF" ]; then
    echo_info "  备份并删除: $MULTUS_CONF"
    sudo cp "$MULTUS_CONF" "$BACKUP_DIR/" 2>/dev/null || true
    sudo rm -f "$MULTUS_CONF"
    echo_info "  ✓ 已删除"
fi

if [ -f "$DAEMON_CONFIG" ]; then
    echo_info "  备份并删除: $DAEMON_CONFIG"
    sudo cp "$DAEMON_CONFIG" "$BACKUP_DIR/" 2>/dev/null || true
    sudo rm -f "$DAEMON_CONFIG"
    echo_info "  ✓ 已删除"
fi

if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  备份并删除: $KUBECONFIG_FILE"
    sudo cp "$KUBECONFIG_FILE" "$BACKUP_DIR/" 2>/dev/null || true
    sudo rm -f "$KUBECONFIG_FILE"
    echo_info "  ✓ 已删除"
fi

# 删除 multus.d 目录（如果为空）
if [ -d "$CNI_CONF_DIR/multus.d" ]; then
    if [ -z "$(sudo ls -A $CNI_CONF_DIR/multus.d 2>/dev/null)" ]; then
        echo_info "  删除空目录: $CNI_CONF_DIR/multus.d"
        sudo rmdir "$CNI_CONF_DIR/multus.d" 2>/dev/null || true
    else
        echo_info "  目录不为空，保留: $CNI_CONF_DIR/multus.d"
        sudo ls -la "$CNI_CONF_DIR/multus.d"
    fi
fi

if [ -d "$BACKUP_DIR" ] && [ "$(sudo ls -A $BACKUP_DIR 2>/dev/null)" ]; then
    echo_info "  备份位置: $BACKUP_DIR"
fi

# 4. 检查是否还有其他 Multus 相关资源
echo ""
echo_info "4. 检查其他 Multus 相关资源"
echo ""

# ServiceAccount（可选，保留以供后续使用）
SA_EXISTS=$(kubectl get sa -n kube-system multus -o name 2>/dev/null || echo "")
if [ -n "$SA_EXISTS" ]; then
    echo_info "  ServiceAccount 'multus' 存在（保留，供后续使用）"
    echo_warn "    如需删除，手动执行: kubectl delete sa -n kube-system multus"
fi

# ClusterRole（可选，保留）
CR_EXISTS=$(kubectl get clusterrole multus -o name 2>/dev/null || echo "")
if [ -n "$CR_EXISTS" ]; then
    echo_info "  ClusterRole 'multus' 存在（保留，供后续使用）"
    echo_warn "    如需删除，手动执行: kubectl delete clusterrole multus"
fi

# ClusterRoleBinding（可选，保留）
CRB_EXISTS=$(kubectl get clusterrolebinding multus -o name 2>/dev/null || echo "")
if [ -n "$CRB_EXISTS" ]; then
    echo_info "  ClusterRoleBinding 'multus' 存在（保留，供后续使用）"
    echo_warn "    如需删除，手动执行: kubectl delete clusterrolebinding multus"
fi

# 5. 检查二进制文件（不删除，因为可能被其他组件使用）
echo ""
echo_info "5. 检查 Multus 二进制文件"
echo ""

MULTUS_BIN_PATHS=(
    "/var/lib/rancher/k3s/data/current/bin/multus-shim"
    "/opt/cni/bin/multus-shim"
)

for bin_path in "${MULTUS_BIN_PATHS[@]}"; do
    if [ -f "$bin_path" ]; then
        echo_info "  找到二进制: $bin_path（保留，不删除）"
    fi
done

# 6. 验证清理结果
echo ""
echo_info "6. 验证清理结果"
echo ""

# 检查 DaemonSet
if kubectl get daemonset -n kube-system kube-multus-ds > /dev/null 2>&1; then
    echo_warn "  ⚠️  DaemonSet 仍然存在"
else
    echo_info "  ✓ DaemonSet 已删除"
fi

# 检查 Pods
MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_PODS" ]; then
    echo_warn "  ⚠️  仍有 Pods 存在"
else
    echo_info "  ✓ 所有 Pods 已删除"
fi

# 检查配置文件
if [ -f "$MULTUS_CONF" ]; then
    echo_warn "  ⚠️  配置文件仍然存在: $MULTUS_CONF"
else
    echo_info "  ✓ 配置文件已删除"
fi

echo ""
echo_info "=========================================="
echo_info "清理完成"
echo_info "=========================================="
echo ""
echo_info "已删除："
echo "  - Multus DaemonSet 和 Pods"
echo "  - Multus 配置文件（已备份到 $BACKUP_DIR）"
echo ""
echo_info "保留："
echo "  - ServiceAccount, ClusterRole, ClusterRoleBinding（供后续使用）"
echo "  - Multus 二进制文件（可能被其他组件使用）"
echo "  - CRD（NetworkAttachmentDefinition，不应删除）"
echo ""
echo_info "现在可以重新安装 Multus，使用官方推荐方式"
echo ""

