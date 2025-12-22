#!/bin/bash

# 诊断 Rook Operator Pod 无法启动的问题

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "诊断 Rook Operator Pod 问题"
echo_info "=========================================="
echo ""

POD_NAME=$(kubectl get pods -n rook-ceph -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo_error "未找到 Rook Operator Pod"
    exit 1
fi

echo_info "Pod: $POD_NAME"
echo ""

# 1. 检查 Pod 状态
echo_info "1. Pod 状态"
kubectl get pod -n rook-ceph $POD_NAME
echo ""

# 2. 检查 Pod 事件
echo_info "2. Pod 事件"
kubectl describe pod -n rook-ceph $POD_NAME | grep -A 20 "Events:"
echo ""

# 3. 检查 Pod 详情
echo_info "3. Pod 详情（关键字段）"
echo "  容器状态:"
kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.status.containerStatuses[*].state}' | jq '.' 2>/dev/null || kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.status.containerStatuses[*].state}'
echo ""
echo "  等待原因:"
kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "无"
echo ""

# 4. 检查节点资源
echo_info "4. 节点资源"
NODE_NAME=$(kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
if [ -n "$NODE_NAME" ]; then
    echo "  节点: $NODE_NAME"
    kubectl describe node $NODE_NAME | grep -A 10 "Allocated resources:"
else
    echo_warn "  Pod 尚未调度到节点"
fi
echo ""

# 5. 检查镜像拉取
echo_info "5. 镜像信息"
IMAGE=$(kubectl get pod -n rook-ceph $POD_NAME -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
echo "  镜像: $IMAGE"
echo "  检查镜像是否可拉取..."
echo "  （如果镜像拉取失败，可能需要配置镜像加速器）"
echo ""

# 6. 常见问题检查
echo_info "6. 常见问题检查"
echo ""

# 检查是否是 Multus 问题
if kubectl describe pod -n rook-ceph $POD_NAME 2>/dev/null | grep -q "multus\|CNI\|network"; then
    echo_warn "  ⚠️  可能是 Multus 网络问题"
    echo "  检查 Multus 状态:"
    kubectl get pods -n kube-system -l app=multus
fi

# 检查是否是资源不足
if kubectl describe pod -n rook-ceph $POD_NAME 2>/dev/null | grep -q "Insufficient\|OOM"; then
    echo_warn "  ⚠️  可能是资源不足"
fi

# 检查是否是镜像拉取问题
if kubectl describe pod -n rook-ceph $POD_NAME 2>/dev/null | grep -q "ImagePull\|ErrImagePull\|Pull"; then
    echo_warn "  ⚠️  可能是镜像拉取问题"
    echo "  尝试手动拉取镜像:"
    echo "    sudo crictl pull $IMAGE"
fi

echo ""
echo_info "=========================================="
echo_info "诊断完成"
echo_info "=========================================="
echo ""
echo_info "请将上面的输出信息发给我，特别是："
echo "  1. Pod 事件（Events）"
echo "  2. 等待原因（waiting.reason）"
echo "  3. 是否有 Multus 相关错误"
echo ""

