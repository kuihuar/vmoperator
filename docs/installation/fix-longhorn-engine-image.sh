#!/bin/bash

# 修复 Longhorn 引擎镜像问题

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
echo_info "修复 Longhorn 引擎镜像问题"
echo_info "=========================================="
echo ""

# 1. 检查当前引擎镜像
echo_info "1. 检查当前 Longhorn 引擎镜像："
kubectl get engineimage -n longhorn-system -o wide
echo ""

# 2. 检查引擎镜像状态
echo_info "2. 检查引擎镜像详细信息："
ENGINE_IMAGE=$(kubectl get engineimage -n longhorn-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${ENGINE_IMAGE}" ]; then
    echo_info "  引擎镜像: ${ENGINE_IMAGE}"
    kubectl get engineimage ${ENGINE_IMAGE} -n longhorn-system -o yaml | grep -A 10 "status:" | head -15
else
    echo_warn "  未找到引擎镜像"
fi
echo ""

# 3. 检查 Longhorn 设置
echo_info "3. 检查 Longhorn 设置（disableRevisionCounter）："
kubectl get settings.longhorn.io disable-revision-counter -n longhorn-system -o yaml 2>/dev/null | grep -A 5 "value:" || echo "  设置不存在或无法读取"
echo ""

# 4. 解决方案
echo_info "=========================================="
echo_info "解决方案"
echo_info "=========================================="
echo ""

echo_warn "问题：当前引擎镜像版本不支持 disable revision counter"
echo ""
echo_info "方案 1：禁用 revision counter（推荐）"
echo_info "  运行以下命令："
echo ""
echo "kubectl patch settings.longhorn.io disable-revision-counter -n longhorn-system --type='merge' -p '{\"value\":\"false\"}'"
echo ""
echo_info "方案 2：等待引擎镜像自动更新"
echo_info "  Longhorn 会自动更新引擎镜像，但可能需要一些时间"
echo ""
echo_info "方案 3：手动更新引擎镜像"
echo_info "  通过 Longhorn UI 更新引擎镜像"
echo ""

read -p "是否执行方案 1（禁用 revision counter）？(y/n，默认y): " APPLY_FIX
APPLY_FIX=${APPLY_FIX:-y}

if [[ $APPLY_FIX =~ ^[Yy]$ ]]; then
    echo_info "  应用修复..."
    if kubectl patch settings.longhorn.io disable-revision-counter -n longhorn-system --type='merge' -p '{"value":"false"}' 2>/dev/null; then
        echo_info "  ✓ 已禁用 revision counter"
        echo_info "  等待几秒后，再次尝试创建 PVC"
        sleep 3
    else
        echo_error "  ✗ 修复失败，可能需要手动操作"
    fi
else
    echo_info "  跳过自动修复"
fi

echo ""
echo_info "验证修复："
kubectl get settings.longhorn.io disable-revision-counter -n longhorn-system -o jsonpath='{.value}' && echo ""
echo ""

