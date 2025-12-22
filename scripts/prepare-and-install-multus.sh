#!/bin/bash

# 检查并安装 Multus

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
echo_info "Multus 安装前检查"
echo_info "=========================================="
echo ""

# 1. 检查是否已安装 Multus
echo_info "1. 检查 Multus 是否已安装"
echo ""

MULTUS_DS=$(kubectl get daemonset -n kube-system kube-multus-ds -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_DS" ]; then
    echo_warn "  ⚠️  Multus DaemonSet 已存在"
    echo_info "  当前状态:"
    kubectl get daemonset -n kube-system kube-multus-ds
    echo ""
    read -p "是否要继续安装（会覆盖现有配置）？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "安装已取消"
        exit 0
    fi
    echo_warn "  将使用现有安装，继续检查..."
else
    echo_info "  ✓ Multus 未安装，可以继续"
fi

# 2. 检查 RBAC 配置
echo ""
echo_info "2. 检查 RBAC 配置"
echo ""

RBAC_OK=true

# 检查 ServiceAccount
if kubectl get sa -n kube-system multus > /dev/null 2>&1; then
    echo_info "  ✓ ServiceAccount 存在"
else
    echo_warn "  ⚠️  ServiceAccount 不存在，将在安装时创建"
    RBAC_OK=false
fi

# 检查 ClusterRole
if kubectl get clusterrole multus > /dev/null 2>&1; then
    echo_info "  ✓ ClusterRole 存在"
    # 检查权限是否正确
    HAS_GET=$(kubectl get clusterrole multus -o yaml | grep -A 10 "pods:" | grep -q "get" && echo "yes" || echo "no")
    HAS_UPDATE=$(kubectl get clusterrole multus -o yaml | grep -A 10 "pods:" | grep -q "update" && echo "yes" || echo "no")
    if [ "$HAS_GET" != "yes" ] || [ "$HAS_UPDATE" != "yes" ]; then
        echo_warn "  ⚠️  ClusterRole 权限可能不完整（需要 get 和 update）"
        RBAC_OK=false
    fi
else
    echo_warn "  ⚠️  ClusterRole 不存在，将在安装时创建"
    RBAC_OK=false
fi

# 检查 ClusterRoleBinding
if kubectl get clusterrolebinding multus > /dev/null 2>&1; then
    echo_info "  ✓ ClusterRoleBinding 存在"
else
    echo_warn "  ⚠️  ClusterRoleBinding 不存在，将在安装时创建"
    RBAC_OK=false
fi

# 3. 检查 kubeconfig
echo ""
echo_info "3. 检查 kubeconfig 配置"
echo ""

KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  ✓ kubeconfig 文件存在: $KUBECONFIG_FILE"
    # 检查文件内容
    if sudo cat "$KUBECONFIG_FILE" | grep -q "token:" && sudo cat "$KUBECONFIG_FILE" | grep -q "certificate-authority-data:"; then
        echo_info "  ✓ kubeconfig 文件格式正确"
    else
        echo_warn "  ⚠️  kubeconfig 文件格式可能有问题"
    fi
else
    echo_warn "  ⚠️  kubeconfig 文件不存在，将在安装时创建"
fi

# 4. 检查 Multus 配置文件
echo ""
echo_info "4. 检查 Multus 配置文件"
echo ""

MULTUS_CONF="/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf"
if [ -f "$MULTUS_CONF" ]; then
    echo_info "  ✓ Multus 配置文件存在"
    KUBECONFIG_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // ""' 2>/dev/null || echo "")
    if [ -n "$KUBECONFIG_PATH" ]; then
        echo_info "  kubeconfig 路径: $KUBECONFIG_PATH"
        if [ "$KUBECONFIG_PATH" = "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig" ]; then
            echo_info "  ✓ 路径正确"
        else
            echo_warn "  ⚠️  路径可能需要调整"
        fi
    fi
else
    echo_info "  ✓ 配置文件不存在（将在安装时创建）"
fi

# 5. 检查 k3s CNI 目录
echo ""
echo_info "5. 检查 k3s CNI 配置目录"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if [ -d "$CNI_CONF_DIR" ]; then
    echo_info "  ✓ CNI 配置目录存在: $CNI_CONF_DIR"
    sudo ls -la "$CNI_CONF_DIR" | head -5
else
    echo_error "  ✗ CNI 配置目录不存在"
    exit 1
fi

# 6. 总结检查结果
echo ""
echo_info "=========================================="
echo_info "检查总结"
echo_info "=========================================="
echo ""

if [ "$RBAC_OK" = true ] && [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "✓ 所有必要的配置都已存在"
    echo_info "可以继续安装 Multus"
else
    echo_warn "⚠️  部分配置缺失，安装过程会创建这些配置"
fi

echo ""
read -p "是否继续安装 Multus？(Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo_info "安装已取消"
    exit 0
fi

echo ""
echo_info "=========================================="
echo_info "开始安装 Multus"
echo_info "=========================================="
echo ""

# 安装步骤
# 1. 确保 RBAC 配置正确
echo_info "步骤 1: 配置 RBAC"
echo ""
if [ "$RBAC_OK" != true ]; then
    echo_info "  创建/更新 RBAC 配置..."
    ./scripts/fix-multus-rbac.sh
else
    echo_info "  ✓ RBAC 配置已存在，跳过"
fi

# 2. 确保 kubeconfig 存在
echo ""
echo_info "步骤 2: 配置 kubeconfig"
echo ""
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo_info "  创建 kubeconfig..."
    sudo ./scripts/create-kubeconfig-official.sh
else
    echo_info "  ✓ kubeconfig 已存在，验证有效性..."
    if sudo cat "$KUBECONFIG_FILE" | grep -q "token:"; then
        echo_info "  ✓ kubeconfig 看起来有效"
    else
        echo_warn "  ⚠️  kubeconfig 可能无效，重新创建..."
        sudo ./scripts/create-kubeconfig-official.sh
    fi
fi

# 3. 安装 Multus（使用 kubectl apply 方式，适合 k3s）
echo ""
echo_info "步骤 3: 安装 Multus DaemonSet"
echo ""

if [ -n "$MULTUS_DS" ]; then
    echo_info "  Multus 已安装，检查是否需要更新..."
    echo_info "  如果出现问题，可以运行: ./scripts/cleanup-multus-installation.sh 清理后重新安装"
else
    echo_info "  使用 kubectl apply 安装 Multus..."
    
    # 使用项目的安装脚本
    if [ -f "./scripts/install-multus-kubectl-k3s.sh" ]; then
        echo_info "  运行安装脚本..."
        sudo ./scripts/install-multus-kubectl-k3s.sh
    else
        echo_error "  ✗ 安装脚本不存在: ./scripts/install-multus-kubectl-k3s.sh"
        exit 1
    fi
fi

# 4. 验证安装
echo ""
echo_info "步骤 4: 验证安装"
echo ""

sleep 5

# 检查 DaemonSet
if kubectl get daemonset -n kube-system kube-multus-ds > /dev/null 2>&1; then
    echo_info "  ✓ DaemonSet 已创建"
    kubectl get daemonset -n kube-system kube-multus-ds
else
    echo_error "  ✗ DaemonSet 未创建"
fi

# 检查 Pods
echo ""
echo_info "  检查 Pods 状态:"
kubectl get pods -n kube-system -l app=multus || echo_warn "  未找到 Multus Pods"

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "下一步："
echo "  1. 等待 Multus Pods 进入 Running 状态"
echo "  2. 检查日志: kubectl logs -n kube-system -l app=multus"
echo "  3. 测试创建 Pod 验证 Multus 是否正常工作"
echo ""

