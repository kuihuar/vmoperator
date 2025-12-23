#!/bin/bash

# 清理 Wukong VM 资源

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

VM_NAME="${1}"
NAMESPACE="${2:-default}"

echo ""
echo_info "=========================================="
echo_info "清理 Wukong VM 资源"
echo_info "=========================================="
echo ""

# 如果没有指定 VM 名称，尝试从文件获取
if [ -z "$VM_NAME" ]; then
    YAML_FILE="config/samples/vm_v1alpha1_wukong_separated_disks.yaml"
    
    if [ -f "$YAML_FILE" ]; then
        VM_NAME=$(grep "^  name:" "$YAML_FILE" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
        NAMESPACE=$(grep "^  namespace:" "$YAML_FILE" | head -1 | awk '{print $2}' | tr -d '"' || echo "default")
        
        if [ -z "$VM_NAME" ]; then
            VM_NAME=$(grep "metadata:" -A 5 "$YAML_FILE" | grep "name:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
        fi
    fi
    
    if [ -z "$VM_NAME" ]; then
        echo_error "  无法自动获取 VM 名称"
        echo ""
        echo_info "  用法: $0 <vm-name> [namespace]"
        echo "    或: $0  # 自动从 config/samples/vm_v1alpha1_wukong_separated_disks.yaml 获取"
        exit 1
    fi
fi

echo_info "  VM 名称: $VM_NAME"
echo_info "  命名空间: $NAMESPACE"
echo ""

# 确认
echo_warn "  将删除以下资源："
echo "    - Wukong VM: $VM_NAME"
echo "    - 相关 PVC"
echo "    - 相关 Pod"
echo ""
read -p "确认要继续吗？(yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo_info "已取消"
    exit 0
fi

echo ""

# 1. 删除 Wukong VM
echo_info "步骤 1: 删除 Wukong VM"
echo ""

if kubectl get wukong "$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo_info "  删除 Wukong: $VM_NAME"
    kubectl delete wukong "$VM_NAME" -n "$NAMESPACE" --ignore-not-found=true
    
    echo_info "  等待 VM 删除（30秒）..."
    sleep 30
else
    echo_info "  Wukong VM 不存在: $VM_NAME"
fi

echo ""

# 2. 删除相关的 Pod（VM Pod、CDI Pod 等）
echo_info "步骤 2: 删除相关 Pod"
echo ""

# 查找与 VM 相关的 Pod
POD_LIST=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | jq -r ".items[] | select(.metadata.name | contains(\"$VM_NAME\")) | .metadata.name" 2>/dev/null || echo "")

if [ -n "$POD_LIST" ]; then
    echo "$POD_LIST" | while read pod; do
        if [ -n "$pod" ]; then
            echo_info "  删除 Pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        fi
    done
else
    echo_info "  未找到相关的 Pod"
fi

# 删除 importer Pod（CDI 创建的）
IMPORTER_PODS=$(kubectl get pods -n "$NAMESPACE" -l cdi.kubevirt.io -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | contains("importer")) | .metadata.name' 2>/dev/null || echo "")

if [ -n "$IMPORTER_PODS" ]; then
    echo "$IMPORTER_PODS" | while read pod; do
        if [ -n "$pod" ]; then
            echo_info "  删除 importer Pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        fi
    done
fi

echo ""

# 3. 删除相关的 PVC
echo_info "步骤 3: 删除相关 PVC"
echo ""

# 查找与 VM 相关的 PVC（名称通常以 VM 名称开头）
PVC_LIST=$(kubectl get pvc -n "$NAMESPACE" -o json 2>/dev/null | jq -r ".items[] | select(.metadata.name | startswith(\"$VM_NAME\")) | .metadata.name" 2>/dev/null || echo "")

if [ -n "$PVC_LIST" ]; then
    echo "$PVC_LIST" | while read pvc; do
        if [ -n "$pvc" ]; then
            echo_info "  删除 PVC: $pvc"
            kubectl delete pvc "$pvc" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        fi
    done
    
    echo_info "  等待 PVC 删除（30秒）..."
    sleep 30
else
    echo_info "  未找到相关的 PVC"
fi

echo ""

# 4. 删除相关的 DataVolume（如果存在）
echo_info "步骤 4: 删除相关 DataVolume"
echo ""

DV_LIST=$(kubectl get datavolume -n "$NAMESPACE" -o json 2>/dev/null | jq -r ".items[] | select(.metadata.name | startswith(\"$VM_NAME\")) | .metadata.name" 2>/dev/null || echo "")

if [ -n "$DV_LIST" ]; then
    echo "$DV_LIST" | while read dv; do
        if [ -n "$dv" ]; then
            echo_info "  删除 DataVolume: $dv"
            kubectl delete datavolume "$dv" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        fi
    done
else
    echo_info "  未找到相关的 DataVolume"
fi

echo ""

# 5. 删除相关的 PV（如果有未绑定的）
echo_info "步骤 5: 检查相关的 PV"
echo ""

PV_LIST=$(kubectl get pv -o json 2>/dev/null | jq -r ".items[] | select(.spec.claimRef.namespace == \"$NAMESPACE\" and (.spec.claimRef.name | startswith(\"$VM_NAME\"))) | .metadata.name" 2>/dev/null || echo "")

if [ -n "$PV_LIST" ]; then
    echo "$PV_LIST" | while read pv; do
        if [ -n "$pv" ]; then
            PV_STATUS=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$PV_STATUS" = "Released" ]; then
                echo_info "  删除 Released 状态的 PV: $pv"
                kubectl delete pv "$pv" --ignore-not-found=true 2>/dev/null || true
            else
                echo_info "  PV $pv 状态为 $PV_STATUS，跳过删除"
            fi
        fi
    done
else
    echo_info "  未找到相关的 PV"
fi

echo ""

# 6. 最终验证
echo_info "步骤 6: 验证清理结果"
echo ""

# 检查 Wukong VM
if kubectl get wukong "$VM_NAME" -n "$NAMESPACE" &>/dev/null 2>&1; then
    echo_warn "  ⚠️  Wukong VM 仍然存在: $VM_NAME"
else
    echo_info "  ✓ Wukong VM 已删除"
fi

# 检查相关 Pod
REMAINING_PODS=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | jq -r ".items[] | select(.metadata.name | contains(\"$VM_NAME\")) | .metadata.name" 2>/dev/null || echo "")
if [ -n "$REMAINING_PODS" ]; then
    echo_warn "  ⚠️  仍有相关 Pod 存在"
    echo "$REMAINING_PODS"
else
    echo_info "  ✓ 相关 Pod 已删除"
fi

# 检查相关 PVC
REMAINING_PVC=$(kubectl get pvc -n "$NAMESPACE" -o json 2>/dev/null | jq -r ".items[] | select(.metadata.name | startswith(\"$VM_NAME\")) | .metadata.name" 2>/dev/null || echo "")
if [ -n "$REMAINING_PVC" ]; then
    echo_warn "  ⚠️  仍有相关 PVC 存在"
    echo "$REMAINING_PVC"
else
    echo_info "  ✓ 相关 PVC 已删除"
fi

echo ""

# 总结
echo_info "=========================================="
echo_info "清理完成"
echo_info "=========================================="
echo ""

echo_info "已清理的资源："
echo "  - Wukong VM: $VM_NAME"
echo "  - 相关 Pod"
echo "  - 相关 PVC"
echo "  - 相关 DataVolume"
echo ""

echo_info "如果还有残留资源，可以手动删除："
echo "  kubectl get wukong -n $NAMESPACE"
echo "  kubectl get pods -n $NAMESPACE | grep $VM_NAME"
echo "  kubectl get pvc -n $NAMESPACE | grep $VM_NAME"
echo ""

