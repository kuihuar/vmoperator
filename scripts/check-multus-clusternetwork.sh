#!/bin/bash

# 检查 Multus clusterNetwork 配置（只检查，不修改）

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_detail() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 Multus clusterNetwork 配置"
echo_info "=========================================="
echo ""
echo_warn "⚠️  这是只读检查，不会修改任何配置"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# 1. 检查 Multus 配置文件
echo_info "1. 检查 Multus 配置文件"
echo ""

if [ ! -f "$MULTUS_CONF" ]; then
    echo_error "  ✗ Multus 配置文件不存在: $MULTUS_CONF"
    exit 1
fi

echo_info "  ✓ 配置文件存在: $MULTUS_CONF"
echo ""

# 2. 读取当前配置
echo_info "2. 当前 Multus 配置"
echo ""

CURRENT_CLUSTER_NETWORK=$(sudo cat "$MULTUS_CONF" | jq -r '.clusterNetwork // "未配置"' 2>/dev/null || echo "无法读取")

echo_detail "  当前 clusterNetwork: $CURRENT_CLUSTER_NETWORK"
echo ""

# 3. 查找 k3s 实际使用的默认 CNI
echo_info "3. 查找 k3s 默认 CNI"
echo ""

DEFAULT_CNI_CONF=$(sudo ls -1 "$CNI_CONF_DIR"/*.conf 2>/dev/null | grep -v multus | head -1 || echo "")
DEFAULT_CNI_NAME=""

if [ -n "$DEFAULT_CNI_CONF" ]; then
    echo_detail "  找到默认 CNI 配置: $DEFAULT_CNI_CONF"
    DEFAULT_CNI_NAME=$(sudo cat "$DEFAULT_CNI_CONF" | jq -r '.name // ""' 2>/dev/null || echo "")
    
    if [ -z "$DEFAULT_CNI_NAME" ]; then
        DEFAULT_CNI_NAME=$(basename "$DEFAULT_CNI_CONF" .conf)
    fi
    
    echo_detail "  默认 CNI 名称: $DEFAULT_CNI_NAME"
    
    # 显示默认 CNI 配置内容
    echo ""
    echo_detail "  默认 CNI 配置内容:"
    sudo cat "$DEFAULT_CNI_CONF" | jq '.' 2>/dev/null | head -10 || sudo cat "$DEFAULT_CNI_CONF" | head -10
else
    echo_warn "  ⚠️  未找到默认 CNI 配置"
    DEFAULT_CNI_NAME="flannel"  # k3s 常见默认值
    echo_detail "  将使用默认值: $DEFAULT_CNI_NAME"
fi

echo ""

# 4. 对比分析
echo_info "4. 配置对比分析"
echo ""

if [ "$CURRENT_CLUSTER_NETWORK" = "$DEFAULT_CNI_NAME" ]; then
    echo_info "  ✓ clusterNetwork 配置正确: $CURRENT_CLUSTER_NETWORK"
    echo_info "  ✓ 无需修改"
else
    echo_warn "  ⚠️  clusterNetwork 配置不匹配:"
    echo_detail "    当前值: $CURRENT_CLUSTER_NETWORK"
    echo_detail "    应该值: $DEFAULT_CNI_NAME"
    echo ""
    echo_warn "  ⚠️  这可能导致 Pod 无法创建（如 Rook Operator）"
    echo ""
    echo_info "  建议修复:"
    echo "    sudo ./scripts/fix-multus-clusternetwork.sh"
    echo ""
    echo_info "  或者手动修复:"
    echo "    sudo sed -i 's|\"clusterNetwork\": \"$CURRENT_CLUSTER_NETWORK\"|\"clusterNetwork\": \"$DEFAULT_CNI_NAME\"|g' $MULTUS_CONF"
fi

echo ""

# 5. 检查 Multus Pod 状态
echo_info "5. Multus Pod 状态"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    POD_STATUS=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo_detail "  Pod: $MULTUS_POD"
    echo_detail "  状态: $POD_STATUS"
    
    if [ "$POD_STATUS" = "Running" ]; then
        echo_info "  ✓ Multus Pod 运行正常"
    else
        echo_warn "  ⚠️  Multus Pod 状态异常"
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

echo ""

# 6. 检查是否有 Pod 因为 Multus 问题无法启动
echo_info "6. 检查受影响的 Pod"
echo ""

FAILED_PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason? == "CreateContainerError" or .status.containerStatuses[]?.state.waiting.reason? == "CreateContainerConfigError") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$FAILED_PODS" ]; then
    echo_warn "  ⚠️  发现可能受影响的 Pod:"
    echo "$FAILED_PODS" | while read pod; do
        if [ -n "$pod" ]; then
            echo_detail "    - $pod"
        fi
    done
else
    echo_info "  ✓ 未发现明显受影响的 Pod"
fi

echo ""
echo_info "=========================================="
echo_info "检查完成"
echo_info "=========================================="
echo ""

