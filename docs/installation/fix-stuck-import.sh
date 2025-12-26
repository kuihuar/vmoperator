#!/bin/bash

# 修复卡住的导入过程
# 用于解决 DataVolume ImportScheduled 和 Volume 无法附加的问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

DV_NAME="${1:-ubuntu-rulai-system}"
NAMESPACE="${2:-default}"

echo ""
echo_info "修复卡住的导入过程: ${NAMESPACE}/${DV_NAME}"
echo ""

# 1. 检查 DataVolume 状态
echo_info "1. 检查 DataVolume 状态..."
DV_PHASE=$(kubectl get datavolume "${DV_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
echo "   Phase: ${DV_PHASE}"

if [ "${DV_PHASE}" = "NotFound" ]; then
    echo_warn "  DataVolume 不存在，无需修复"
    exit 0
fi

# 2. 查找临时 PVC
echo_info "2. 查找临时 PVC..."
TEMP_PVC=$(kubectl get pvc -n "${NAMESPACE}" -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.name | test("^prime-")) | .metadata.name' 2>/dev/null | head -1 || echo "")

if [ -n "${TEMP_PVC}" ]; then
    echo "   临时 PVC: ${TEMP_PVC}"
    TEMP_PV=$(kubectl get pvc "${TEMP_PVC}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
    if [ -n "${TEMP_PV}" ]; then
        echo "   关联的 PV: ${TEMP_PV}"
    fi
else
    echo "   未找到临时 PVC"
fi

# 3. 查找 importer Pod
echo_info "3. 查找 importer Pod..."
IMPORTER_POD=$(kubectl get pods -n "${NAMESPACE}" -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.name | test("importer-prime-")) | .metadata.name' 2>/dev/null | head -1 || echo "")

if [ -n "${IMPORTER_POD}" ]; then
    echo "   Importer Pod: ${IMPORTER_POD}"
    POD_PHASE=$(kubectl get pod "${IMPORTER_POD}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
    echo "   Phase: ${POD_PHASE}"
else
    echo "   未找到 importer Pod"
fi

# 4. 确认操作
echo ""
echo_warn "将执行以下操作："
echo "  1. 删除 DataVolume: ${NAMESPACE}/${DV_NAME}"
if [ -n "${TEMP_PVC}" ]; then
    echo "  2. 删除临时 PVC: ${NAMESPACE}/${TEMP_PVC}"
fi
if [ -n "${IMPORTER_POD}" ]; then
    echo "  3. 删除 importer Pod: ${NAMESPACE}/${IMPORTER_POD}"
fi
if [ -n "${TEMP_PV}" ]; then
    echo "  4. 删除 Longhorn Volume: ${TEMP_PV}"
fi
echo "  5. 等待资源清理完成"
echo "  6. 提示重新应用 Wukong CRD"
echo ""
read -p "确认继续？(y/n，默认n): " CONFIRM
CONFIRM=${CONFIRM:-n}

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo_info "已取消"
    exit 0
fi

# 5. 执行清理
echo ""
echo_info "开始清理..."

# 删除 DataVolume
echo_info "  删除 DataVolume..."
kubectl delete datavolume "${DV_NAME}" -n "${NAMESPACE}" 2>/dev/null || true

# 删除临时 PVC
if [ -n "${TEMP_PVC}" ]; then
    echo_info "  删除临时 PVC..."
    kubectl delete pvc "${TEMP_PVC}" -n "${NAMESPACE}" 2>/dev/null || true
fi

# 删除 importer Pod
if [ -n "${IMPORTER_POD}" ]; then
    echo_info "  删除 importer Pod..."
    kubectl delete pod "${IMPORTER_POD}" -n "${NAMESPACE}" 2>/dev/null || true
fi

# 删除 Longhorn Volume（如果存在）
if [ -n "${TEMP_PV}" ]; then
    echo_info "  检查并删除 Longhorn Volume..."
    if kubectl get volumes.longhorn.io "${TEMP_PV}" -n longhorn-system &>/dev/null; then
        # 先尝试清理 finalizers
        kubectl patch volumes.longhorn.io "${TEMP_PV}" -n longhorn-system \
            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
        sleep 2
        kubectl delete volumes.longhorn.io "${TEMP_PV}" -n longhorn-system 2>/dev/null || true
    fi
fi

# 等待资源清理
echo_info "  等待资源清理完成（10秒）..."
sleep 10

# 6. 验证清理结果
echo ""
echo_info "验证清理结果..."
REMAINING_DV=$(kubectl get datavolume "${DV_NAME}" -n "${NAMESPACE}" 2>/dev/null | wc -l || echo "0")
REMAINING_PVC=$(kubectl get pvc -n "${NAMESPACE}" | grep -c "prime-" || echo "0")
REMAINING_POD=$(kubectl get pods -n "${NAMESPACE}" | grep -c "importer-prime-" || echo "0")

if [ "${REMAINING_DV}" -eq 0 ] && [ "${REMAINING_PVC}" -eq 0 ] && [ "${REMAINING_POD}" -eq 0 ]; then
    echo_info "  ✓ 清理完成"
else
    echo_warn "  ⚠️  仍有残留资源，请手动检查"
fi

# 7. 提示下一步
echo ""
echo_info "下一步操作："
echo "  1. 重新应用 Wukong CRD 以触发重新创建："
echo "     kubectl apply -f config/samples/vm_v1alpha1_wukong_rulai.yaml"
echo ""
echo "  2. 或者，如果不需要从镜像导入，可以编辑 Wukong CRD 移除 disk.image 字段："
echo "     kubectl edit wukong ubuntu-rulai -n default"
echo ""

