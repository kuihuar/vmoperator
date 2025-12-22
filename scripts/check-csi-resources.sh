#!/bin/bash

# 检查 CSI 相关资源

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 CSI 相关资源"
echo_info "=========================================="
echo ""

# 1. 检查所有 CSI 相关的 DaemonSet
echo_info "1. CSI DaemonSets"
echo ""
kubectl get daemonset -n rook-ceph -o wide | head -1
kubectl get daemonset -n rook-ceph -o wide | grep -E "csi|NAME" || echo_warn "  未找到 CSI DaemonSet"
echo ""

# 2. 检查所有 CSI 相关的 Deployment
echo_info "2. CSI Deployments"
echo ""
kubectl get deployment -n rook-ceph -o wide | head -1
kubectl get deployment -n rook-ceph -o wide | grep -E "csi|NAME" || echo_warn "  未找到 CSI Deployment"
echo ""

# 3. 检查所有 CSI 相关的 Pods
echo_info "3. CSI Pods"
echo ""
kubectl get pods -n rook-ceph -o wide | head -1
kubectl get pods -n rook-ceph -o wide | grep csi || echo_warn "  未找到 CSI Pods"
echo ""

# 4. 检查 CSI 相关的所有资源（使用标签）
echo_info "4. 使用标签查找 CSI 资源"
echo ""
echo "  app=csi-rbdplugin:"
kubectl get all -n rook-ceph -l app=csi-rbdplugin 2>/dev/null || echo_warn "  未找到"
echo ""
echo "  app=csi-cephfsplugin:"
kubectl get all -n rook-ceph -l app=csi-cephfsplugin 2>/dev/null || echo_warn "  未找到"
echo ""

# 5. 检查 CSI Driver CRD
echo_info "5. CSI Driver"
echo ""
kubectl get csidriver 2>/dev/null | grep rook || echo_warn "  未找到 rook CSI Driver"
echo ""

# 6. 检查 StorageClass
echo_info "6. StorageClass"
echo ""
kubectl get storageclass | grep rook || echo_warn "  未找到 rook StorageClass"
echo ""

# 7. 检查是否有 CSI 相关的 ConfigMap 或 Secret
echo_info "7. CSI 配置"
echo ""
echo "  ConfigMaps:"
kubectl get configmap -n rook-ceph | grep csi || echo_warn "  未找到 CSI ConfigMap"
echo ""
echo "  Secrets:"
kubectl get secret -n rook-ceph | grep csi || echo_warn "  未找到 CSI Secret"
echo ""

# 8. 检查 CephCluster 的 CSI 配置
echo_info "8. CephCluster CSI 配置"
echo ""
CSI_CONFIG=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.spec.csi}' 2>/dev/null || echo "")
if [ -z "$CSI_CONFIG" ]; then
    echo_warn "  ⚠️  CephCluster 中没有 CSI 配置"
else
    echo "$CSI_CONFIG" | jq '.' 2>/dev/null || echo "$CSI_CONFIG"
fi
echo ""

echo_info "=========================================="
echo_info "检查完成"
echo_info "=========================================="

