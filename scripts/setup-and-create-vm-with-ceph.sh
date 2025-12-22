#!/bin/bash

# 完整步骤：设置环境并创建使用 Ceph 存储的 VM

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
echo_info "设置环境并创建使用 Ceph 存储的 VM"
echo_info "=========================================="
echo ""

# 步骤 1: 安装 Wukong CRD
echo_info "步骤 1: 安装 Wukong CRD"
echo ""

if kubectl get crd wukongs.vm.novasphere.dev &>/dev/null; then
    echo_info "  ✓ Wukong CRD 已存在"
else
    echo_info "  安装 Wukong CRD..."
    ./scripts/install-wukong-crd.sh
    if [ $? -ne 0 ]; then
        echo_error "  ✗ CRD 安装失败"
        exit 1
    fi
fi

echo ""

# 步骤 2: 配置单节点调度
echo_info "步骤 2: 配置单节点调度"
echo ""

./scripts/fix-kubevirt-single-node.sh

echo ""

# 步骤 3: 验证 Ceph StorageClass
echo_info "步骤 3: 验证 Ceph StorageClass"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    echo_info "  ✓ Ceph StorageClass 存在"
    kubectl get storageclass rook-ceph-block
else
    echo_error "  ✗ Ceph StorageClass 不存在"
    echo_warn "  请先安装 Ceph: ./scripts/install-ceph-rook.sh"
    exit 1
fi

echo ""

# 步骤 4: 检查 Ceph 集群状态
echo_info "步骤 4: 检查 Ceph 集群状态"
echo ""

CEPH_CLUSTER=$(kubectl get cephcluster rook-ceph -n rook-ceph 2>/dev/null || echo "")
if [ -z "$CEPH_CLUSTER" ]; then
    echo_error "  ✗ Ceph 集群未找到"
    echo_warn "  请先安装 Ceph: ./scripts/install-ceph-rook.sh"
    exit 1
fi

CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [ "$CEPH_PHASE" = "Ready" ]; then
    echo_info "  ✓ Ceph 集群状态: Ready"
else
    echo_warn "  ⚠️  Ceph 集群状态: $CEPH_PHASE"
    echo_warn "  集群可能还在初始化中，但可以继续"
fi

echo ""

# 步骤 5: 创建 VM
echo_info "步骤 5: 创建 VM"
echo ""

VM_FILE="config/samples/vm_v1alpha1_wukong_ceph_test.yaml"

if [ ! -f "$VM_FILE" ]; then
    echo_error "  ✗ VM 配置文件不存在: $VM_FILE"
    exit 1
fi

echo_info "  使用配置文件: $VM_FILE"
echo ""

read -p "是否创建 VM? (y/n，默认y): " CREATE_VM
CREATE_VM=${CREATE_VM:-y}

if [ "$CREATE_VM" != "y" ]; then
    echo_info "  已取消"
    exit 0
fi

echo_info "  创建 VM..."
kubectl apply -f "$VM_FILE"

echo ""

# 步骤 6: 监控 VM 创建
echo_info "步骤 6: 监控 VM 创建过程"
echo ""

VM_NAME="ubuntu-ceph-test"

echo_info "  查看 Wukong 资源状态:"
kubectl get wukong "$VM_NAME" -w &
WUKONG_PID=$!

sleep 10
kill $WUKONG_PID 2>/dev/null || true

echo ""
echo_info "  当前状态:"
kubectl get wukong "$VM_NAME"
echo ""

echo_info "  相关资源:"
kubectl get vm,vmi,pvc -l app.kubernetes.io/name=novasphere 2>/dev/null || echo "  暂无相关资源"
echo ""

echo_info "  PVC 状态:"
kubectl get pvc | grep "$VM_NAME" || echo "  暂无 PVC"
echo ""

echo_info "=========================================="
echo_info "设置完成"
echo_info "=========================================="
echo ""

echo_info "后续操作:"
echo "  1. 查看 Wukong 状态: kubectl get wukong $VM_NAME"
echo "  2. 查看 VM 状态: kubectl get vm"
echo "  3. 查看 VMI 状态: kubectl get vmi"
echo "  4. 查看 PVC 状态: kubectl get pvc"
echo "  5. 查看详细事件: kubectl describe wukong $VM_NAME"
echo ""

