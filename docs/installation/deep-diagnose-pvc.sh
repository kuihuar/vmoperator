#!/bin/bash

# 深度诊断 PVC 问题
# 检查残留资源、Longhorn 状态、磁盘空间等

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
echo_section "深度诊断 PVC 问题"
echo ""

# ==========================================
# 1. 检查残留的 Volume 资源
# ==========================================
echo_section "1. 检查残留的 Longhorn Volume"
echo "----------------------------------------"
VOLUMES=$(kubectl get volumes.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.name)\t\(.status.state // "unknown")\t\(.status.robustness // "unknown")"' 2>/dev/null || echo "")

if [ -z "${VOLUMES}" ]; then
    echo_info "✓ 没有残留的 Volume"
else
    echo_warn "发现以下 Volume:"
    echo "Volume Name | State | Robustness"
    echo "----------------------------------------"
    while IFS=$'\t' read -r vol_name state robustness; do
        if [ -z "${vol_name}" ]; then
            continue
        fi
        printf "%-50s | %-10s | %s\n" "${vol_name}" "${state}" "${robustness}"
        
        # 检查是否有 finalizers 阻止删除
        FINALIZERS=$(kubectl get volumes.longhorn.io "${vol_name}" -n longhorn-system \
            -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
        if [ -n "${FINALIZERS}" ]; then
            echo_warn "  ⚠️  有 finalizers: ${FINALIZERS}"
        fi
        
        # 检查 Volume 的详细状态
        if [ "${state}" = "faulted" ] || [ "${robustness}" = "faulted" ]; then
            echo_error "  ✗ Volume 处于故障状态"
            echo "  详细信息:"
            kubectl get volumes.longhorn.io "${vol_name}" -n longhorn-system -o yaml 2>/dev/null | \
                grep -A 30 "status:" | head -40 || true
        fi
    done <<< "${VOLUMES}"
fi
echo ""

# ==========================================
# 2. 检查残留的 PVC
# ==========================================
echo_section "2. 检查所有 PVC 状态"
echo "----------------------------------------"
kubectl get pvc -A
echo ""

# 检查 Pending 的 PVC
PENDING_PVC=$(kubectl get pvc -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.phase == "Pending" or .status.phase == "") | "\(.metadata.namespace)\t\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "${PENDING_PVC}" ]; then
    echo_warn "Pending 状态的 PVC:"
    while IFS=$'\t' read -r ns name; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "  ${ns}/${name}"
        
        # 检查 PVC 的 finalizers
        FINALIZERS=$(kubectl get pvc "${name}" -n "${ns}" \
            -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
        if [ -n "${FINALIZERS}" ]; then
            echo_warn "    ⚠️  有 finalizers: ${FINALIZERS}"
        fi
        
        # 检查 PVC 事件
        echo "    最近事件:"
        kubectl get events -n "${ns}" --field-selector involvedObject.name="${name}" \
            --sort-by='.lastTimestamp' -o wide 2>/dev/null | tail -5 || echo "      无事件"
    done <<< "${PENDING_PVC}"
fi
echo ""

# ==========================================
# 3. 检查 Engine 和 Replica Pod
# ==========================================
echo_section "3. 检查 Engine 和 Replica Pod"
echo "----------------------------------------"
ENGINE_PODS=$(kubectl get pods -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.name | test("engine-|replica-")) | "\(.metadata.name)\t\(.status.phase)"' 2>/dev/null || echo "")

if [ -z "${ENGINE_PODS}" ]; then
    echo_info "✓ 没有 Engine/Replica Pod"
else
    echo_warn "发现 Engine/Replica Pod:"
    while IFS=$'\t' read -r name phase; do
        if [ -z "${name}" ]; then
            continue
        fi
        echo "  ${name}: ${phase}"
        if [ "${phase}" != "Running" ] && [ "${phase}" != "Succeeded" ]; then
            echo "    状态详情:"
            kubectl get pod "${name}" -n longhorn-system -o jsonpath='{.status.containerStatuses[*].state}' 2>/dev/null || true
            echo ""
        fi
    done <<< "${ENGINE_PODS}"
fi
echo ""

# ==========================================
# 4. 检查 Longhorn 节点状态和磁盘空间
# ==========================================
echo_section "4. Longhorn 节点状态和磁盘空间"
echo "----------------------------------------"
NODE_NAME=$(kubectl get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "host1")
if [ -n "${NODE_NAME}" ]; then
    echo_info "节点: ${NODE_NAME}"
    
    # 获取节点详细信息
    NODE_YAML=$(kubectl get nodes.longhorn.io "${NODE_NAME}" -n longhorn-system -o yaml 2>/dev/null || echo "")
    if [ -n "${NODE_YAML}" ]; then
        # 检查调度状态
        ALLOW_SCHEDULING=$(echo "${NODE_YAML}" | grep -A 5 "allowScheduling:" | head -2 || echo "")
        echo "  调度配置:"
        echo "${ALLOW_SCHEDULING}" | sed 's/^/    /'
        
        # 检查磁盘状态
        echo ""
        echo "  磁盘状态:"
        echo "${NODE_YAML}" | grep -A 20 "disks:" | head -25 | sed 's/^/    /' || echo "    无磁盘信息"
        
        # 检查条件
        echo ""
        echo "  节点条件:"
        echo "${NODE_YAML}" | grep -A 10 "conditions:" | head -15 | sed 's/^/    /' || echo "    无条件信息"
    fi
fi
echo ""

# 检查实际磁盘空间（如果可能）
echo_info "检查 Longhorn 数据路径磁盘空间:"
LONGHORN_DATA_PATH=$(kubectl get configmap -n longhorn-system longhorn-storageclass \
    -o jsonpath='{.data.longhorn-storageclass\.yaml}' 2>/dev/null | \
    grep -oP 'path:\s*\K[^\s]+' | head -1 || echo "/var/lib/longhorn")

echo "  数据路径: ${LONGHORN_DATA_PATH}"
echo "  注意: 需要在节点上执行 'df -h ${LONGHORN_DATA_PATH}' 来检查实际磁盘空间"
echo ""

# ==========================================
# 5. 检查 Longhorn Manager 日志中的错误
# ==========================================
echo_section "5. Longhorn Manager 最近错误日志"
echo "----------------------------------------"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${MANAGER_POD}" ]; then
    echo_info "Manager Pod: ${MANAGER_POD}"
    echo ""
    echo "  最近包含 'error' 或 'faulted' 的日志 (最后 30 行):"
    kubectl logs "${MANAGER_POD}" -n longhorn-system --tail=200 2>/dev/null | \
        grep -iE "error|faulted|failed|pvc-" | tail -30 || echo "    无相关错误日志"
else
    echo_warn "⚠️  未找到 Longhorn Manager Pod"
fi
echo ""

# ==========================================
# 6. 检查 StorageClass 和 Provisioner
# ==========================================
echo_section "6. StorageClass 和 Provisioner 状态"
echo "----------------------------------------"
echo_info "StorageClass:"
kubectl get storageclass longhorn -o yaml 2>/dev/null | grep -A 5 "provisioner:\|parameters:" || \
    echo_warn "  StorageClass 'longhorn' 不存在"
echo ""

echo_info "Longhorn CSI Provisioner Pod:"
PROVISIONER_POD=$(kubectl get pods -n longhorn-system -l app=csi-provisioner \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${PROVISIONER_POD}" ]; then
    echo "  Pod: ${PROVISIONER_POD}"
    kubectl get pod "${PROVISIONER_POD}" -n longhorn-system -o wide
    echo ""
    echo "  最近日志 (最后 20 行):"
    kubectl logs "${PROVISIONER_POD}" -n longhorn-system --tail=20 2>/dev/null || true
else
    echo_warn "  ⚠️  未找到 CSI Provisioner Pod"
    echo "  查找所有 CSI 相关 Pod:"
    kubectl get pods -n longhorn-system | grep -i csi || echo "    无 CSI Pod"
fi
echo ""

# ==========================================
# 7. 检查 DataVolume 和 Import Populator
# ==========================================
echo_section "7. DataVolume 和 Import Populator 状态"
echo "----------------------------------------"
echo_info "DataVolume:"
kubectl get datavolume -A 2>/dev/null || echo "  无 DataVolume"
echo ""

echo_info "Import Populator Pod:"
IMPORT_POPULATOR=$(kubectl get pods -A -l app=import-populator \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${IMPORT_POPULATOR}" ]; then
    echo "  Pod: ${IMPORT_POPULATOR}"
    kubectl get pod "${IMPORT_POPULATOR}" -A -o wide
else
    echo "  查找所有 import 相关 Pod:"
    kubectl get pods -A | grep -i import || echo "    无 import Pod"
fi
echo ""

# ==========================================
# 8. 检查 Wukong CRD 配置
# ==========================================
echo_section "8. Wukong CRD 配置检查"
echo "----------------------------------------"
WUKONG_CRDS=$(kubectl get wukong -A -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)"' 2>/dev/null || echo "")

if [ -z "${WUKONG_CRDS}" ]; then
    echo_info "✓ 没有 Wukong CRD"
else
    echo_warn "发现 Wukong CRD:"
    while IFS=$'\t' read -r ns name; do
        if [ -z "${ns}" ] || [ -z "${name}" ]; then
            continue
        fi
        echo_info "  ${ns}/${name}"
        
        # 检查磁盘配置
        DISKS=$(kubectl get wukong "${name}" -n "${ns}" -o jsonpath='{.spec.disks[*].name}' 2>/dev/null || echo "")
        if [ -n "${DISKS}" ]; then
            echo "    磁盘: ${DISKS}"
            for disk in ${DISKS}; do
                IMAGE=$(kubectl get wukong "${name}" -n "${ns}" \
                    -o jsonpath="{.spec.disks[?(@.name==\"${disk}\")].image}" 2>/dev/null || echo "")
                STORAGE_CLASS=$(kubectl get wukong "${name}" -n "${ns}" \
                    -o jsonpath="{.spec.disks[?(@.name==\"${disk}\")].storageClassName}" 2>/dev/null || echo "")
                SIZE=$(kubectl get wukong "${name}" -n "${ns}" \
                    -o jsonpath="{.spec.disks[?(@.name==\"${disk}\")].size}" 2>/dev/null || echo "")
                echo "      ${disk}: size=${SIZE}, storageClass=${STORAGE_CLASS}, image=${IMAGE:-none}"
            done
        fi
    done <<< "${WUKONG_CRDS}"
fi
echo ""

# ==========================================
# 9. 总结和建议
# ==========================================
echo_section "诊断总结"
echo "----------------------------------------"
echo_info "已检查的项目:"
echo "  ✓ 残留的 Longhorn Volume"
echo "  ✓ PVC 状态和 finalizers"
echo "  ✓ Engine/Replica Pod"
echo "  ✓ Longhorn 节点状态"
echo "  ✓ Longhorn Manager 日志"
echo "  ✓ CSI Provisioner 状态"
echo "  ✓ DataVolume 和 Import Populator"
echo "  ✓ Wukong CRD 配置"
echo ""
echo_warn "下一步建议:"
echo "  1. 如果发现残留的故障 Volume，需要清理 finalizers 后删除"
echo "  2. 检查节点磁盘空间是否充足"
echo "  3. 检查 Longhorn Manager 日志中的具体错误"
echo "  4. 确认 StorageClass 配置正确"
echo "  5. 如果问题持续，考虑重启 Longhorn Manager Pod"
echo ""

