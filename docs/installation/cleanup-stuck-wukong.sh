#!/bin/bash
# 清理卡住的 Wukong 资源及其相关资源
# 用法: ./cleanup-stuck-wukong.sh <wukong-name> [namespace]

set -e

WUKONG_NAME="${1:-ubuntu-vm-dual-network-test}"
NAMESPACE="${2:-default}"

echo "=========================================="
echo "清理卡住的 Wukong 资源"
echo "=========================================="
echo "Wukong 名称: $WUKONG_NAME"
echo "命名空间: $NAMESPACE"
echo ""

# 检查 Wukong 资源是否存在
if ! kubectl get wukong "$WUKONG_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Wukong 资源不存在: $WUKONG_NAME"
    exit 1
fi

echo "1. 检查 Wukong 资源状态..."
WUKONG_STATUS=$(kubectl get wukong "$WUKONG_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
VM_NAME=$(kubectl get wukong "$WUKONG_NAME" -n "$NAMESPACE" -o jsonpath='{.status.vmName}' 2>/dev/null || echo "")
echo "   状态: $WUKONG_STATUS"
echo "   VM 名称: $VM_NAME"

# 获取 PVC 列表
PVC_NAMES=$(kubectl get wukong "$WUKONG_NAME" -n "$NAMESPACE" -o jsonpath='{.status.volumes[*].pvcName}' 2>/dev/null || echo "")
echo "   PVC 列表: $PVC_NAMES"
echo ""

# 2. 删除 VirtualMachine（如果存在）
if [ -n "$VM_NAME" ]; then
    echo "2. 删除 VirtualMachine: $VM_NAME"
    if kubectl get vm "$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
        kubectl delete vm "$VM_NAME" -n "$NAMESPACE" --force --grace-period=0 2>&1 || true
        echo "   ✅ VirtualMachine 删除命令已执行"
        # 等待删除完成
        echo "   等待 VirtualMachine 删除完成..."
        for i in {1..30}; do
            if ! kubectl get vm "$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
                echo "   ✅ VirtualMachine 已删除"
                break
            fi
            sleep 1
        done
    else
        echo "   ℹ️  VirtualMachine 不存在"
    fi
    echo ""
fi

# 3. 删除 DataVolume（如果存在）
echo "3. 删除 DataVolume..."
for pvc_name in $PVC_NAMES; do
    if [ -n "$pvc_name" ]; then
        echo "   检查 DataVolume: $pvc_name"
        if kubectl get datavolume "$pvc_name" -n "$NAMESPACE" &>/dev/null; then
            kubectl delete datavolume "$pvc_name" -n "$NAMESPACE" --force --grace-period=0 2>&1 || true
            echo "   ✅ DataVolume $pvc_name 删除命令已执行"
        else
            echo "   ℹ️  DataVolume $pvc_name 不存在"
        fi
    fi
done
echo ""

# 4. 删除 PVC（如果 DataVolume 已删除或不存在）
echo "4. 删除 PVC..."
for pvc_name in $PVC_NAMES; do
    if [ -n "$pvc_name" ]; then
        echo "   检查 PVC: $pvc_name"
        if kubectl get pvc "$pvc_name" -n "$NAMESPACE" &>/dev/null; then
            # 检查是否有 finalizer
            FINALIZERS=$(kubectl get pvc "$pvc_name" -n "$NAMESPACE" -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
            if [[ "$FINALIZERS" == *"kubernetes.io/pvc-protection"* ]]; then
                echo "   ⚠️  PVC 有保护 finalizer，尝试移除..."
                kubectl patch pvc "$pvc_name" -n "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>&1 || true
            fi
            kubectl delete pvc "$pvc_name" -n "$NAMESPACE" --force --grace-period=0 2>&1 || true
            echo "   ✅ PVC $pvc_name 删除命令已执行"
        else
            echo "   ℹ️  PVC $pvc_name 不存在"
        fi
    fi
done
echo ""

# 5. 等待资源删除完成
echo "5. 等待资源删除完成..."
sleep 5

# 6. 手动移除 Wukong 的 finalizer（如果资源已删除但 finalizer 还在）
echo "6. 检查并移除 Wukong finalizer..."
FINALIZERS=$(kubectl get wukong "$WUKONG_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
if [ -n "$FINALIZERS" ]; then
    echo "   当前 finalizers: $FINALIZERS"
    echo "   移除 finalizer..."
    kubectl patch wukong "$WUKONG_NAME" -n "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>&1 || true
    echo "   ✅ Finalizer 已移除"
else
    echo "   ℹ️  没有 finalizer"
fi
echo ""

# 7. 删除 Wukong 资源
echo "7. 删除 Wukong 资源..."
if kubectl get wukong "$WUKONG_NAME" -n "$NAMESPACE" &>/dev/null; then
    kubectl delete wukong "$WUKONG_NAME" -n "$NAMESPACE" --force --grace-period=0 2>&1 || true
    echo "   ✅ Wukong 删除命令已执行"
else
    echo "   ℹ️  Wukong 资源不存在"
fi
echo ""

echo "=========================================="
echo "清理完成！"
echo "=========================================="
echo ""
echo "验证资源是否已删除："
echo "  kubectl get wukong $WUKONG_NAME -n $NAMESPACE"
echo "  kubectl get vm $VM_NAME -n $NAMESPACE 2>/dev/null || echo 'VM 已删除'"
for pvc_name in $PVC_NAMES; do
    if [ -n "$pvc_name" ]; then
        echo "  kubectl get pvc $pvc_name -n $NAMESPACE 2>/dev/null || echo 'PVC 已删除'"
    fi
done

