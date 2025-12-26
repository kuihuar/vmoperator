#!/bin/bash

# 修复 Longhorn PVC 问题
# 1. 诊断 PVC Pending 和卷附加失败问题
# 2. 处理 importer Pod 问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "诊断和修复 Longhorn PVC 问题"
echo_info "=========================================="
echo ""

# 1. 检查所有 PVC 状态
echo_info "1. 检查 PVC 状态..."
echo "----------------------------------------"
kubectl get pvc -A
echo ""

# 2. 检查 Pending 的 PVC
PENDING_PVC=$(kubectl get pvc -A -o jsonpath='{range .items[?(@.status.phase=="Pending")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
if [ -n "${PENDING_PVC}" ]; then
    echo_warn "发现 Pending 状态的 PVC:"
    echo "${PENDING_PVC}"
    echo ""
    
    while IFS=$'\t' read -r ns name; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "检查 PVC: ${ns}/${name}"
        echo "  Events:"
        kubectl get events -n "${ns}" --field-selector involvedObject.name="${name}" --sort-by='.lastTimestamp' | tail -5 || true
        echo ""
    done <<< "${PENDING_PVC}"
fi

# 3. 检查有问题的卷
echo_info "2. 检查有问题的 Longhorn Volume..."
echo "----------------------------------------"

# 获取所有 PVC 的 PV 名称
kubectl get pvc -A -o json | jq -r '.items[] | select(.spec.volumeName != null) | "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.volumeName)"' 2>/dev/null | while IFS=$'\t' read -r ns pvc_name pv_name; do
    if [ -z "${pv_name}" ]; then
        continue
    fi
    
    echo_info "检查 Volume: ${pv_name} (PVC: ${ns}/${pvc_name})"
    
    # 检查 Longhorn Volume 状态
    if kubectl get volumes.longhorn.io "${pv_name}" -n longhorn-system &>/dev/null; then
        VOLUME_STATE=$(kubectl get volumes.longhorn.io "${pv_name}" -n longhorn-system -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
        VOLUME_ROBUSTNESS=$(kubectl get volumes.longhorn.io "${pv_name}" -n longhorn-system -o jsonpath='{.status.robustness}' 2>/dev/null || echo "unknown")
        VOLUME_NODE=$(kubectl get volumes.longhorn.io "${pv_name}" -n longhorn-system -o jsonpath='{.spec.nodeID}' 2>/dev/null || echo "")
        
        echo "  State: ${VOLUME_STATE}"
        echo "  Robustness: ${VOLUME_ROBUSTNESS}"
        echo "  Node: ${VOLUME_NODE}"
        
        if [ "${VOLUME_STATE}" != "attached" ] && [ "${VOLUME_STATE}" != "attaching" ]; then
            echo_warn "  ⚠️  Volume 未附加，尝试附加..."
            CURRENT_NODE=$(hostname 2>/dev/null || echo "host1")
            kubectl patch volumes.longhorn.io "${pv_name}" -n longhorn-system --type='merge' -p "{\"spec\":{\"nodeID\":\"${CURRENT_NODE}\"}}" 2>/dev/null || true
            echo_info "  ✓ 已尝试附加到节点: ${CURRENT_NODE}"
        fi
        
        if [ "${VOLUME_ROBUSTNESS}" != "healthy" ] && [ "${VOLUME_ROBUSTNESS}" != "unknown" ]; then
            echo_error "  ✗ Volume 健康状态异常: ${VOLUME_ROBUSTNESS}"
        fi
    else
        echo_warn "  ⚠️  Longhorn Volume ${pv_name} 不存在"
    fi
    echo ""
done

# 4. 检查 importer Pod
echo_info "3. 检查 importer Pod..."
echo "----------------------------------------"
IMPORTER_PODS=$(kubectl get pods -A -o jsonpath='{range .items[?(@.metadata.name=~"importer-.*")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
if [ -n "${IMPORTER_PODS}" ]; then
    echo_warn "发现 importer Pod:"
    echo "${IMPORTER_PODS}"
    echo ""
    
    while IFS=$'\t' read -r ns name; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "检查 Pod: ${ns}/${name}"
        
        # 获取 Pod 的 owner
        OWNER=$(kubectl get pod "${name}" -n "${ns}" -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
        if [ -n "${OWNER}" ]; then
            echo "  Owner: ${OWNER}"
        fi
        
        # 检查 DataVolume
        DV_NAME=$(echo "${name}" | sed 's/importer-prime-//' | sed 's/-[0-9a-f-]*$//' 2>/dev/null || echo "")
        if [ -n "${DV_NAME}" ]; then
            echo "  可能的 DataVolume: ${DV_NAME}"
            if kubectl get datavolume "${DV_NAME}" -n "${ns}" &>/dev/null; then
                DV_PHASE=$(kubectl get datavolume "${DV_NAME}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
                echo "  DataVolume Phase: ${DV_PHASE}"
                
                if [ "${DV_PHASE}" = "Succeeded" ]; then
                    echo_warn "  ⚠️  DataVolume 已完成，importer Pod 应该可以删除"
                    echo_info "  删除 importer Pod:"
                    echo "    kubectl delete pod ${name} -n ${ns}"
                    echo ""
                    echo_info "  如果 Pod 被重新创建，删除 DataVolume（PVC 已创建，可以删除 DataVolume）:"
                    echo "    kubectl delete datavolume ${DV_NAME} -n ${ns}"
                fi
            fi
        fi
        
        # 检查 Pod 状态
        POD_PHASE=$(kubectl get pod "${name}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        echo "  Pod Phase: ${POD_PHASE}"
        
        if [ "${POD_PHASE}" = "Pending" ] || [ "${POD_PHASE}" = "Error" ]; then
            echo "  Events:"
            kubectl get events -n "${ns}" --field-selector involvedObject.name="${name}" --sort-by='.lastTimestamp' | tail -5 || true
        fi
        echo ""
    done <<< "${IMPORTER_PODS}"
else
    echo_info "未发现 importer Pod"
fi

# 5. 检查 Longhorn Manager 状态
echo_info "4. 检查 Longhorn Manager..."
echo "----------------------------------------"
kubectl get pods -n longhorn-system -l app=longhorn-manager
echo ""

# 6. 检查 Longhorn 节点状态
echo_info "5. 检查 Longhorn 节点状态..."
echo "----------------------------------------"
kubectl get nodes.longhorn.io -n longhorn-system -o wide || true
echo ""

# 7. 提供修复建议
echo_info "=========================================="
echo_info "修复建议"
echo_info "=========================================="
echo ""

echo_info "对于卷附加失败问题："
echo "1. 检查 Longhorn Volume 状态："
echo "   kubectl get volumes.longhorn.io <VOLUME_NAME> -n longhorn-system -o yaml"
echo ""
echo "2. 如果 Volume 处于 detached 状态，手动附加："
echo "   kubectl patch volumes.longhorn.io <VOLUME_NAME> -n longhorn-system --type='merge' -p '{\"spec\":{\"nodeID\":\"host1\"}}'"
echo ""
echo "3. 检查节点磁盘空间和 Longhorn 数据路径："
echo "   kubectl get nodes.longhorn.io -n longhorn-system"
echo ""

echo_info "对于 importer Pod 问题："
echo "1. 如果 DataVolume 已完成（Phase=Succeeded），可以删除 importer Pod："
echo "   kubectl delete pod importer-prime-<ID> -n <NAMESPACE>"
echo ""
echo "2. 如果 Pod 被重新创建，删除 DataVolume（PVC 已存在，DataVolume 可以删除）："
echo "   kubectl delete datavolume <DV_NAME> -n <NAMESPACE>"
echo ""
echo "3. 检查 Wukong CRD，如果不需要 image 导入，移除 disk.image 字段"
echo ""

echo_info "对于 PVC Pending 问题："
echo "1. 检查 PVC 事件："
echo "   kubectl describe pvc <PVC_NAME> -n <NAMESPACE>"
echo ""
echo "2. 检查 StorageClass："
echo "   kubectl get storageclass longhorn -o yaml"
echo ""
echo "3. 检查 Longhorn Volume 是否已创建："
echo "   kubectl get volumes.longhorn.io -n longhorn-system"
echo ""

echo ""

