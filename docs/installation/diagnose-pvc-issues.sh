#!/bin/bash

# 诊断 PVC 问题（仅查询，不修复）
# 用于诊断：
# 1. PVC Pending 问题
# 2. 卷附加失败问题
# 3. importer Pod 问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
echo_section() { echo -e "${CYAN}=== $1 ===${NC}"; }

echo ""
echo_section "Longhorn PVC 问题诊断（仅查询，不修复）"
echo ""

# ==========================================
# 1. 检查所有 PVC 状态
# ==========================================
echo_section "1. PVC 状态概览"
echo "----------------------------------------"
kubectl get pvc -A -o wide
echo ""

# ==========================================
# 2. 检查 Pending 的 PVC
# ==========================================
echo_section "2. Pending 状态的 PVC 详情"
echo "----------------------------------------"
PENDING_PVC=$(kubectl get pvc -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.phase == "Pending" or .status.phase == "") | "\(.metadata.namespace)\t\(.metadata.name)"' 2>/dev/null || echo "")

if [ -z "${PENDING_PVC}" ]; then
    echo_info "✓ 没有 Pending 状态的 PVC"
else
    echo_warn "发现 Pending 状态的 PVC:"
    echo ""
    while IFS=$'\t' read -r ns name; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "PVC: ${ns}/${name}"
        echo "  └─ 详细信息:"
        kubectl get pvc "${name}" -n "${ns}" -o yaml 2>/dev/null | grep -A 10 "status:\|spec:" || true
        echo ""
        echo "  └─ 事件 (最近 10 条):"
        kubectl get events -n "${ns}" --field-selector involvedObject.name="${name}" \
            --sort-by='.lastTimestamp' -o wide 2>/dev/null | tail -10 || echo "    无事件"
        echo ""
        echo "  └─ 关联的 PV:"
        PV_NAME=$(kubectl get pvc "${name}" -n "${ns}" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
        if [ -n "${PV_NAME}" ]; then
            echo "     PV: ${PV_NAME}"
            kubectl get pv "${PV_NAME}" -o yaml 2>/dev/null | grep -A 5 "status:\|spec:" || true
        else
            echo "     ⚠️  PVC 尚未绑定到 PV"
        fi
        echo ""
        echo "  └─ 关联的 DataVolume (如果存在):"
        DV_NAME=$(kubectl get datavolume -n "${ns}" -o json 2>/dev/null | \
            jq -r ".items[] | select(.spec.pvc.name == \"${name}\") | .metadata.name" 2>/dev/null || echo "")
        if [ -n "${DV_NAME}" ]; then
            echo "     DataVolume: ${DV_NAME}"
            DV_PHASE=$(kubectl get datavolume "${DV_NAME}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
            echo "     Phase: ${DV_PHASE}"
            kubectl get datavolume "${DV_NAME}" -n "${ns}" -o yaml 2>/dev/null | grep -A 10 "status:" || true
        else
            echo "     ✓ 无关联的 DataVolume"
        fi
        echo ""
        echo "----------------------------------------"
    done <<< "${PENDING_PVC}"
fi
echo ""

# ==========================================
# 3. 检查所有 Longhorn Volume 状态
# ==========================================
echo_section "3. Longhorn Volume 状态"
echo "----------------------------------------"
VOLUMES=$(kubectl get volumes.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.name)\t\(.status.state // "unknown")\t\(.status.robustness // "unknown")\t\(.spec.nodeID // "none")"' 2>/dev/null || echo "")

if [ -z "${VOLUMES}" ]; then
    echo_warn "⚠️  未找到 Longhorn Volume"
else
    echo "Volume Name | State | Robustness | Node"
    echo "----------------------------------------"
    while IFS=$'\t' read -r vol_name state robustness node; do
        if [ -z "${vol_name}" ]; then
            continue
        fi
        printf "%-40s | %-10s | %-10s | %s\n" "${vol_name}" "${state}" "${robustness}" "${node}"
    done <<< "${VOLUMES}"
    echo ""
    
    # 检查有问题的 Volume
    echo_info "检查有问题的 Volume:"
    while IFS=$'\t' read -r vol_name state robustness node; do
        if [ -z "${vol_name}" ]; then
            continue
        fi
        
        ISSUES=()
        if [ "${state}" != "attached" ] && [ "${state}" != "attaching" ] && [ "${state}" != "unknown" ]; then
            ISSUES+=("状态异常: ${state}")
        fi
        if [ "${robustness}" != "healthy" ] && [ "${robustness}" != "unknown" ] && [ "${robustness}" != "" ]; then
            ISSUES+=("健康状态异常: ${robustness}")
        fi
        
        if [ ${#ISSUES[@]} -gt 0 ]; then
            echo_warn "  ⚠️  ${vol_name}:"
            for issue in "${ISSUES[@]}"; do
                echo "     - ${issue}"
            done
            
            # 获取 Volume 详细信息
            echo "     详细信息:"
            kubectl get volumes.longhorn.io "${vol_name}" -n longhorn-system -o yaml 2>/dev/null | \
                grep -A 20 "status:" | head -25 || true
            echo ""
        fi
    done <<< "${VOLUMES}"
fi
echo ""

# ==========================================
# 4. 检查卷附加失败的问题
# ==========================================
echo_section "4. 卷附加失败问题"
echo "----------------------------------------"
# 查找所有有 FailedAttachVolume 事件的 Pod
FAILED_ATTACH=$(kubectl get events -A --field-selector reason=FailedAttachVolume \
    --sort-by='.lastTimestamp' -o json 2>/dev/null | \
    jq -r '.items[] | "\(.involvedObject.namespace)\t\(.involvedObject.name)\t\(.message)"' 2>/dev/null | \
    tail -20 || echo "")

if [ -z "${FAILED_ATTACH}" ]; then
    echo_info "✓ 未发现卷附加失败事件"
else
    echo_warn "发现卷附加失败事件:"
    echo ""
    while IFS=$'\t' read -r ns name message; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "Pod: ${ns}/${name}"
        echo "  消息: ${message}"
        
        # 提取 Volume 名称
        VOL_NAME=$(echo "${message}" | grep -oE 'pvc-[0-9a-f-]+' | head -1 || echo "")
        if [ -n "${VOL_NAME}" ]; then
            echo "  关联的 Volume: ${VOL_NAME}"
            if kubectl get volumes.longhorn.io "${VOL_NAME}" -n longhorn-system &>/dev/null; then
                VOL_STATE=$(kubectl get volumes.longhorn.io "${VOL_NAME}" -n longhorn-system \
                    -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
                VOL_ROBUSTNESS=$(kubectl get volumes.longhorn.io "${VOL_NAME}" -n longhorn-system \
                    -o jsonpath='{.status.robustness}' 2>/dev/null || echo "unknown")
                VOL_NODE=$(kubectl get volumes.longhorn.io "${VOL_NAME}" -n longhorn-system \
                    -o jsonpath='{.spec.nodeID}' 2>/dev/null || echo "none")
                echo "    State: ${VOL_STATE}"
                echo "    Robustness: ${VOL_ROBUSTNESS}"
                echo "    Node: ${VOL_NODE}"
                
                # 检查 Engine
                ENGINE_POD=$(kubectl get pods -n longhorn-system \
                    -l longhorn.io/engine="${VOL_NAME}" -o name 2>/dev/null | head -1 || echo "")
                if [ -n "${ENGINE_POD}" ]; then
                    echo "    Engine Pod: ${ENGINE_POD}"
                    kubectl get "${ENGINE_POD}" -n longhorn-system -o jsonpath='{.status.phase}' 2>/dev/null && echo ""
                fi
                
                # 检查 Replicas
                REPLICA_COUNT=$(kubectl get replicas.longhorn.io -n longhorn-system \
                    -l longhorn.io/volume="${VOL_NAME}" --no-headers 2>/dev/null | wc -l || echo "0")
                echo "    Replicas: ${REPLICA_COUNT}"
                if [ "${REPLICA_COUNT}" -gt 0 ]; then
                    kubectl get replicas.longhorn.io -n longhorn-system \
                        -l longhorn.io/volume="${VOL_NAME}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.currentState}{"\n"}{end}' 2>/dev/null || true
                fi
            else
                echo_warn "    ⚠️  Longhorn Volume ${VOL_NAME} 不存在"
            fi
        fi
        echo ""
    done <<< "${FAILED_ATTACH}"
fi
echo ""

# ==========================================
# 5. 检查 importer Pod
# ==========================================
echo_section "5. Importer Pod 信息"
echo "----------------------------------------"
IMPORTER_PODS=$(kubectl get pods -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.name | test("importer-")) | "\(.metadata.namespace)\t\(.metadata.name)\t\(.status.phase)"' 2>/dev/null || echo "")

if [ -z "${IMPORTER_PODS}" ]; then
    echo_info "✓ 未发现 importer Pod"
else
    echo_warn "发现 importer Pod:"
    echo ""
    while IFS=$'\t' read -r ns name phase; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "Pod: ${ns}/${name}"
        echo "  Phase: ${phase}"
        
        # 获取 Owner
        OWNER_KIND=$(kubectl get pod "${name}" -n "${ns}" \
            -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
        OWNER_NAME=$(kubectl get pod "${name}" -n "${ns}" \
            -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
        if [ -n "${OWNER_KIND}" ] && [ -n "${OWNER_NAME}" ]; then
            echo "  Owner: ${OWNER_KIND}/${OWNER_NAME}"
        fi
        
        # 尝试从 Pod 名称推断 DataVolume
        DV_NAME=$(echo "${name}" | sed 's/importer-prime-//' | sed 's/-[0-9a-f-]*$//' 2>/dev/null || echo "")
        if [ -n "${DV_NAME}" ]; then
            echo "  可能的 DataVolume: ${DV_NAME}"
            if kubectl get datavolume "${DV_NAME}" -n "${ns}" &>/dev/null; then
                DV_PHASE=$(kubectl get datavolume "${DV_NAME}" -n "${ns}" \
                    -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
                DV_PVC=$(kubectl get datavolume "${DV_NAME}" -n "${ns}" \
                    -o jsonpath='{.spec.pvc.name}' 2>/dev/null || echo "")
                echo "    Phase: ${DV_PHASE}"
                echo "    PVC: ${DV_PVC}"
                
                if [ "${DV_PHASE}" = "Succeeded" ]; then
                    echo_warn "    ⚠️  DataVolume 已完成，importer Pod 理论上可以删除"
                fi
                
                # 检查 DataVolume 的完整状态
                echo "    DataVolume 状态详情:"
                kubectl get datavolume "${DV_NAME}" -n "${ns}" -o yaml 2>/dev/null | \
                    grep -A 15 "status:" || true
            else
                echo "    ⚠️  DataVolume ${DV_NAME} 不存在"
            fi
        fi
        
        # Pod 事件
        echo "  Pod 事件 (最近 5 条):"
        kubectl get events -n "${ns}" --field-selector involvedObject.name="${name}" \
            --sort-by='.lastTimestamp' -o wide 2>/dev/null | tail -5 || echo "    无事件"
        
        # Pod 状态详情
        if [ "${phase}" = "Pending" ] || [ "${phase}" = "Error" ] || [ "${phase}" = "CrashLoopBackOff" ]; then
            echo "  Pod 状态详情:"
            kubectl get pod "${name}" -n "${ns}" -o yaml 2>/dev/null | \
                grep -A 20 "status:" | head -30 || true
        fi
        echo ""
    done <<< "${IMPORTER_PODS}"
fi
echo ""

# ==========================================
# 6. 检查 Longhorn Manager 状态
# ==========================================
echo_section "6. Longhorn Manager 状态"
echo "----------------------------------------"
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' 2>/dev/null || echo "")

if [ -z "${MANAGER_PODS}" ]; then
    echo_error "✗ 未找到 Longhorn Manager Pod"
else
    echo "Manager Pod | Phase"
    echo "----------------------------------------"
    while IFS=$'\t' read -r name phase; do
        if [ -z "${name}" ]; then
            continue
        fi
        printf "%-40s | %s\n" "${name}" "${phase}"
        
        if [ "${phase}" != "Running" ]; then
            echo_warn "  ⚠️  Manager Pod 状态异常"
            kubectl get pod "${name}" -n longhorn-system -o yaml 2>/dev/null | \
                grep -A 10 "status:" | head -15 || true
        fi
    done <<< "${MANAGER_PODS}"
fi
echo ""

# ==========================================
# 7. 检查 Longhorn 节点状态
# ==========================================
echo_section "7. Longhorn 节点状态"
echo "----------------------------------------"
NODES=$(kubectl get nodes.longhorn.io -n longhorn-system -o json 2>/dev/null || echo "")
if [ -z "${NODES}" ] || [ "${NODES}" = "null" ]; then
    echo_warn "⚠️  未找到 Longhorn 节点"
else
    kubectl get nodes.longhorn.io -n longhorn-system -o wide
    echo ""
    echo_info "节点详细信息:"
    kubectl get nodes.longhorn.io -n longhorn-system -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.name)\t\(.status.conditions[]? | select(.type=="Ready") | .status)\t\(.status.allowScheduling // "unknown")"' 2>/dev/null | \
        while IFS=$'\t' read -r node_name ready allow_scheduling; do
            if [ -z "${node_name}" ]; then
                continue
            fi
            echo "  节点: ${node_name}"
            echo "    Ready: ${ready}"
            echo "    AllowScheduling: ${allow_scheduling}"
        done
fi
echo ""

# ==========================================
# 8. 检查 StorageClass
# ==========================================
echo_section "8. StorageClass 配置"
echo "----------------------------------------"
kubectl get storageclass longhorn -o yaml 2>/dev/null | grep -A 20 "metadata:\|parameters:" || \
    echo_warn "⚠️  StorageClass 'longhorn' 不存在"
echo ""

# ==========================================
# 9. 总结
# ==========================================
echo_section "诊断总结"
echo "----------------------------------------"
echo_info "已完成的检查:"
echo "  ✓ PVC 状态"
echo "  ✓ Longhorn Volume 状态"
echo "  ✓ 卷附加失败事件"
echo "  ✓ Importer Pod 信息"
echo "  ✓ Longhorn Manager 状态"
echo "  ✓ Longhorn 节点状态"
echo "  ✓ StorageClass 配置"
echo ""
echo_info "请根据上述信息分析问题原因，然后决定修复方案。"
echo ""

