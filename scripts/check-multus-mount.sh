#!/bin/bash

# 检查 Multus Pod 的挂载情况

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MULTUS_POD" ]; then
    echo_warn "未找到 Multus Pod"
    exit 1
fi

echo_info "检查 Pod: $MULTUS_POD"
echo ""

echo_info "1. 检查 Pod 内的挂载点:"
kubectl exec -n kube-system $MULTUS_POD -- mount | grep -E "cni|net.d" || echo_warn "  未找到相关挂载"

echo ""
echo_info "2. 检查 /etc/cni/net.d 目录:"
kubectl exec -n kube-system $MULTUS_POD -- ls -la /etc/cni/net.d/ 2>&1 || echo_warn "  目录不存在或无法访问"

echo ""
echo_info "3. 检查 /host/etc/cni/net.d 目录（如果挂载了）:"
kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/ 2>&1 || echo_warn "  目录不存在"

echo ""
echo_info "4. 检查配置文件是否存在:"
kubectl exec -n kube-system $MULTUS_POD -- test -f /etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null && echo_info "  ✓ /etc/cni/net.d/multus.d/daemon-config.json 存在" || echo_warn "  ✗ /etc/cni/net.d/multus.d/daemon-config.json 不存在"

kubectl exec -n kube-system $MULTUS_POD -- test -f /host/etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null && echo_info "  ✓ /host/etc/cni/net.d/multus.d/daemon-config.json 存在" || echo_warn "  ✗ /host/etc/cni/net.d/multus.d/daemon-config.json 不存在"

echo ""
echo_info "5. 检查 DaemonSet 挂载配置:"
echo "  主机路径:"
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}'
echo ""
echo "  Pod 内挂载点:"
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}'
echo ""

