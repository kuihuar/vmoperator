#!/bin/bash

# 快速重新创建 Wukong 资源

echo "=== 快速重新创建 Wukong 资源 ==="

WUKONG_NAME="ubuntu-noble-local"
VM_NAME="${WUKONG_NAME}-vm"

# 1. 停止并删除 VM/VMI
echo -e "\n1. 停止并删除 VM/VMI..."
kubectl delete vm "$VM_NAME" --wait=false 2>/dev/null || true
kubectl delete vmi "$VM_NAME" --wait=false 2>/dev/null || true
sleep 3

# 2. 删除存储资源
echo -e "\n2. 删除存储资源..."
kubectl delete datavolume "${WUKONG_NAME}-system" --wait=false 2>/dev/null || true
kubectl delete pvc "${WUKONG_NAME}-system" --wait=false 2>/dev/null || true
sleep 2

# 3. 删除 Wukong
echo -e "\n3. 删除 Wukong..."
kubectl delete wukong "$WUKONG_NAME" --wait=false 2>/dev/null || true
sleep 3

# 4. 重新创建
echo -e "\n4. 重新创建 Wukong..."
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml

# 5. 检查状态
echo -e "\n5. 检查状态..."
sleep 2
kubectl get wukong "$WUKONG_NAME"
kubectl get vm 2>/dev/null | grep "$WUKONG_NAME" || echo "VM 还未创建（等待 controller 处理）"

echo -e "\n=== 完成 ==="
echo ""
echo "等待 Controller 处理..."
echo "检查状态: kubectl get wukong, kubectl get vm, kubectl get vmi"

