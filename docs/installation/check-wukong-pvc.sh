#!/bin/bash

# 检查 wukong PVC 状态

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
echo_info "检查 wukong PVC 状态"
echo_info "=========================================="
echo ""

# 1. 检查 PVC 详细信息
echo_info "1. wukong PVC 详细信息："
kubectl get pvc wukong -o yaml | grep -A 20 "status:" | head -25
echo ""

# 2. 检查 PVC 事件
echo_info "2. wukong PVC 事件："
kubectl describe pvc wukong | grep -A 20 "Events:" | head -25
echo ""

# 3. 检查 Longhorn 状态
echo_info "3. 检查 Longhorn 组件状态："
echo_info "  Longhorn Manager:"
kubectl get pods -n longhorn-system -l app=longhorn-manager | grep -v NAME | head -3
echo ""
echo_info "  Longhorn CSI Plugin:"
kubectl get pods -n longhorn-system -l app=longhorn-csi-plugin | grep -v NAME | head -3
echo ""

# 4. 检查 Longhorn CSI 日志（如果有问题）
echo_info "4. 检查 Longhorn CSI Provisioner 日志（最近 10 行）："
CSI_PROVISIONER=$(kubectl get pods -n longhorn-system -l app=csi-provisioner -o name | head -1 | cut -d'/' -f2)
if [ -n "${CSI_PROVISIONER}" ]; then
    kubectl logs -n longhorn-system ${CSI_PROVISIONER} --tail=10 2>&1 | grep -iE "wukong|error|fail" | head -10 || echo "  未发现相关日志"
else
    echo "  未找到 CSI Provisioner Pod"
fi
echo ""

# 5. 检查 Longhorn Manager 日志
echo_info "5. 检查 Longhorn Manager 日志（最近 10 行）："
LONGHORN_MANAGER=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name | head -1 | cut -d'/' -f2)
if [ -n "${LONGHORN_MANAGER}" ]; then
    kubectl logs -n longhorn-system ${LONGHORN_MANAGER} -c longhorn-manager --tail=10 2>&1 | grep -iE "wukong|error|fail" | head -10 || echo "  未发现相关日志"
else
    echo "  未找到 Longhorn Manager Pod"
fi
echo ""

# 6. 检查 Longhorn 节点状态
echo_info "6. 检查 Longhorn 节点状态："
kubectl get nodes.longhorn.io -n longhorn-system 2>/dev/null | head -5 || echo "  无法获取 Longhorn 节点信息"
echo ""

# 7. 建议
echo_info "=========================================="
echo_info "建议"
echo_info "=========================================="
echo ""
PVC_STATUS=$(kubectl get pvc wukong -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
if [ "${PVC_STATUS}" = "Pending" ]; then
    echo_warn "  PVC 状态为 Pending，可能的原因："
    echo "    1. Longhorn 正在创建卷（通常需要几秒到几分钟）"
    echo "    2. Longhorn 节点未就绪"
    echo "    3. 存储空间不足"
    echo ""
    echo_info "  建议："
    echo "    1. 等待 1-2 分钟，然后再次检查：kubectl get pvc wukong"
    echo "    2. 查看详细事件：kubectl describe pvc wukong"
    echo "    3. 检查 Longhorn UI 中的卷状态"
else
    echo_info "  ✓ PVC 状态正常"
fi
echo ""

