#!/bin/bash

# 手动清理 Longhorn（不依赖脚本，直接执行命令）
# 所有命令都带超时，避免卡住

set +e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "手动清理 Longhorn（所有命令带超时）"
echo_info "=========================================="
echo ""

# 1. 删除所有 PVC（可选）
echo_info "1. 删除所有 PVC（可选，会导致数据丢失）"
read -p "是否删除所有 PVC？(y/n，默认n): " DELETE_PVC
DELETE_PVC=${DELETE_PVC:-n}
if [[ $DELETE_PVC =~ ^[Yy]$ ]]; then
    echo_info "  删除所有 PVC..."
    timeout 30 kubectl delete pvc --all -A 2>&1 || echo_warn "  删除 PVC 超时或失败"
fi
echo ""

# 2. 删除 StorageClass
echo_info "2. 删除 StorageClass..."
timeout 10 kubectl delete storageclass longhorn longhorn-static 2>&1 || true
echo ""

# 3. 先清理所有 Engine Image finalizers
echo_info "3. 清理 Engine Image finalizers..."
kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | .metadata.name' 2>/dev/null | \
    while read name; do
        echo "  清理: ${name}"
        timeout 5 kubectl patch engineimages.longhorn.io "${name}" -n longhorn-system \
            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1 || true
    done || true
echo ""

# 4. 删除所有 Engine Image
echo_info "4. 删除所有 Engine Image..."
kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | .metadata.name' 2>/dev/null | \
    while read name; do
        echo "  删除: ${name}"
        timeout 5 kubectl delete engineimages.longhorn.io "${name}" -n longhorn-system 2>&1 || true
    done || true
echo ""

# 5. 清理 Volume finalizers
echo_info "5. 清理 Volume finalizers..."
kubectl get volumes.longhorn.io -A -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null | \
    while read ns name; do
        timeout 5 kubectl patch volumes.longhorn.io "${name}" -n "${ns}" \
            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1 || true
    done || true
echo ""

# 6. 删除命名空间（带超时）
echo_info "6. 删除 longhorn-system 命名空间..."
timeout 10 kubectl delete namespace longhorn-system 2>&1 || echo_warn "  删除命名空间超时"
echo ""

# 7. 等待并强制清理命名空间（如果还在）
echo_info "7. 等待 5 秒后检查命名空间..."
sleep 5
if kubectl get namespace longhorn-system &>/dev/null; then
    echo_warn "  命名空间仍在，强制清理 finalizers..."
    kubectl get namespace longhorn-system -o json 2>/dev/null | \
        jq '.spec.finalizers = []' 2>/dev/null | \
        kubectl replace --raw /api/v1/namespaces/longhorn-system/finalize -f - 2>&1 || true
    sleep 3
fi
echo ""

# 8. 删除 CRDs（带超时）
echo_info "8. 删除 Longhorn CRDs..."
timeout 10 kubectl delete crd volumes.longhorn.io replicas.longhorn.io engines.longhorn.io nodes.longhorn.io settings.longhorn.io engineimages.longhorn.io backingimagedatasources.longhorn.io backingimagemanagers.longhorn.io backingimages.longhorn.io 2>&1 || true
timeout 10 kubectl delete crd -l app.kubernetes.io/name=longhorn 2>&1 || true
echo ""

# 9. 验证清理结果
echo_info "9. 验证清理结果..."
sleep 3
REMAINING_NS=$(kubectl get namespace longhorn-system 2>/dev/null | wc -l || echo "0")
REMAINING_EI=$(kubectl get engineimages.longhorn.io -n longhorn-system 2>/dev/null | wc -l || echo "0")

if [ "${REMAINING_NS}" -eq 0 ] && [ "${REMAINING_EI}" -eq 0 ]; then
    echo_info "  ✓ 清理完成"
else
    echo_warn "  ⚠️  仍有残留资源"
    if [ "${REMAINING_NS}" -gt 0 ]; then
        echo "    命名空间仍存在"
    fi
    if [ "${REMAINING_EI}" -gt 0 ]; then
        echo "    仍有 Engine Image"
    fi
fi
echo ""

echo_info "清理完成！现在可以重新安装 Longhorn。"
echo ""

