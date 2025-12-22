#!/bin/bash

# 修复 Multus DaemonSet 的挂载路径问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "修复 Multus DaemonSet 挂载路径"
echo ""

# 检查当前配置
DS_NAME="kube-multus-ds"
NAMESPACE="kube-system"

echo_info "当前 DaemonSet 配置:"
kubectl get daemonset -n $NAMESPACE $DS_NAME -o yaml > /tmp/multus-ds-current.yaml

# 检查实际的二进制目录
CNI_BIN_DIR="/var/lib/rancher/k3s/data/current/bin"

if [ ! -d "$CNI_BIN_DIR" ]; then
    echo_error "目录不存在: $CNI_BIN_DIR"
    exit 1
fi

echo_info "目标二进制目录: $CNI_BIN_DIR"
echo ""

# 修复 DaemonSet
echo_info "修复 DaemonSet 配置..."
echo ""

# 方法：直接 patch DaemonSet，修复 init 容器的挂载路径和复制目标
kubectl patch daemonset -n $NAMESPACE $DS_NAME --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "cni",
        "hostPath": {
          "path": "/var/lib/rancher/k3s/agent/etc/cni/net.d",
          "type": "Directory"
        }
      },
      {
        "name": "cnibin",
        "hostPath": {
          "path": "/var/lib/rancher/k3s/data/current/bin",
          "type": "Directory"
        }
      },
      {
        "name": "multus-cfg",
        "hostPath": {
          "path": "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d",
          "type": "DirectoryOrCreate"
        }
      }
    ]
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/initContainers/0/volumeMounts",
    "value": [
      {
        "name": "cnibin",
        "mountPath": "/host/opt/cni/bin"
      }
    ]
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {
        "name": "cni",
        "mountPath": "/host/etc/cni/net.d"
      },
      {
        "name": "cnibin",
        "mountPath": "/host/opt/cni/bin"
      },
      {
        "name": "multus-cfg",
        "mountPath": "/host/etc/cni/net.d/multus.d"
      }
    ]
  }
]' 2>&1

if [ $? -eq 0 ]; then
    echo_info "  ✓ DaemonSet 已修复"
    
    # 删除现有 Pod 让其重新创建
    echo_info "  删除现有 Pod 以应用新配置..."
    kubectl delete pod -n $NAMESPACE -l app=multus --force --grace-period=0 2>/dev/null || true
    
    echo_info "  ✓ Pod 已删除，等待重新创建..."
    sleep 5
else
    echo_error "  ✗ 修复失败"
    exit 1
fi

echo ""
echo_info "检查新的 Pod 状态:"
kubectl get pods -n $NAMESPACE -l app=multus

echo ""

