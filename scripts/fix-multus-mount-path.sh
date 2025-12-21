#!/bin/bash

# 修复 Multus DaemonSet 挂载路径问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复 Multus DaemonSet 挂载路径问题"
echo_info "=========================================="
echo ""

# 1. 检查当前 DaemonSet 配置
echo_info "1. 检查当前 Multus DaemonSet 配置"
echo ""

MULTUS_DS="kube-multus-ds"
NAMESPACE="kube-system"

if ! kubectl get daemonset -n $NAMESPACE $MULTUS_DS &>/dev/null; then
    echo_error "  ✗ 未找到 DaemonSet: $MULTUS_DS"
    exit 1
fi

echo_info "  当前 DaemonSet 的 volumes 配置:"
CURRENT_CNI_VOLUME=$(kubectl get daemonset -n $NAMESPACE $MULTUS_DS -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
CURRENT_CNI_MOUNT=$(kubectl get daemonset -n $NAMESPACE $MULTUS_DS -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

if [ -n "$CURRENT_CNI_VOLUME" ]; then
    echo_info "    主机路径 (hostPath): $CURRENT_CNI_VOLUME"
else
    echo_warn "    ⚠️  未找到 cni volume 配置"
fi

if [ -n "$CURRENT_CNI_MOUNT" ]; then
    echo_info "    Pod 内挂载点 (mountPath): $CURRENT_CNI_MOUNT"
else
    echo_warn "    ⚠️  未找到 cni volumeMount 配置"
fi

# 2. 确认正确的路径
echo ""
echo_info "2. 确认正确的 k3s CNI 路径"
echo ""

K3S_CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if [ ! -d "$K3S_CNI_DIR" ]; then
    echo_error "  ✗ k3s CNI 目录不存在: $K3S_CNI_DIR"
    echo_warn "  请先运行: ./scripts/find-k3s-cni-dir.sh 查找正确路径"
    exit 1
fi

echo_info "  ✓ k3s CNI 目录: $K3S_CNI_DIR"

# 检查配置文件是否存在
CONFIG_FILE="$K3S_CNI_DIR/multus.d/daemon-config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo_info "  ✓ 配置文件存在: $CONFIG_FILE"
else
    echo_warn "  ⚠️  配置文件不存在，需要先创建"
    echo_info "  运行: ./scripts/fix-multus-config-missing.sh"
    exit 1
fi

# 3. 检查挂载是否正确
echo ""
echo_info "3. 检查挂载配置"
echo ""

if [ "$CURRENT_CNI_VOLUME" != "$K3S_CNI_DIR" ]; then
    echo_warn "  ⚠️  挂载路径不正确！"
    echo_warn "    当前: $CURRENT_CNI_VOLUME"
    echo_warn "    应该: $K3S_CNI_DIR"
    echo ""
    echo_info "  需要修复 DaemonSet 挂载配置"
else
    echo_info "  ✓ 挂载路径正确"
    
    # 检查 Pod 内部是否能访问文件
    MULTUS_POD=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$MULTUS_POD" ]; then
        echo ""
        echo_info "  检查 Pod 内部文件访问:"
        if kubectl exec -n $NAMESPACE $MULTUS_POD -- test -f /etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null; then
            echo_info "    ✓ Pod 内可以访问配置文件"
            echo_warn "    但 Pod 仍然报错，可能是其他问题"
        else
            echo_error "    ✗ Pod 内无法访问配置文件"
            echo_warn "    可能需要修复挂载或重启 Pod"
        fi
    fi
    
    echo ""
    echo_warn "  如果挂载路径正确但 Pod 仍无法访问，可能需要："
    echo "    1. 删除 Pod 让其重新创建"
    echo "    2. 检查文件权限"
    echo "    3. 检查 DaemonSet 的其他配置"
    exit 0
fi

# 4. 修复 DaemonSet
echo ""
echo_info "4. 修复 DaemonSet 挂载路径"
echo ""

read -p "是否修复 DaemonSet 挂载路径? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_warn "  已取消"
    exit 0
fi

echo_info "  备份当前 DaemonSet..."
kubectl get daemonset -n $NAMESPACE $MULTUS_DS -o yaml > /tmp/multus-ds-backup-$(date +%Y%m%d-%H%M%S).yaml
echo_info "  ✓ 备份保存到: /tmp/multus-ds-backup-*.yaml"

echo ""
echo_info "  更新 DaemonSet..."

# 检查是否有 cnibin volume
CNIBIN_PATH="/var/lib/rancher/k3s/data/current/bin"
if [ ! -d "$CNIBIN_PATH" ]; then
    # 尝试其他可能的路径
    CNIBIN_PATH=$(sudo find /var/lib/rancher/k3s -type d -name "bin" -path "*/current/bin" 2>/dev/null | head -1 || echo "/opt/cni/bin")
    echo_warn "  使用备选 CNI bin 路径: $CNIBIN_PATH"
fi

# 更新 DaemonSet
kubectl patch daemonset -n $NAMESPACE $MULTUS_DS --type json -p "[
  {
    \"op\": \"replace\",
    \"path\": \"/spec/template/spec/containers/0/volumeMounts\",
    \"value\": [
      {
        \"name\": \"cni\",
        \"mountPath\": \"/host/etc/cni/net.d\"
      },
      {
        \"name\": \"cnibin\",
        \"mountPath\": \"/host/opt/cni/bin\"
      }
    ]
  },
  {
    \"op\": \"replace\",
    \"path\": \"/spec/template/spec/volumes\",
    \"value\": [
      {
        \"name\": \"cni\",
        \"hostPath\": {
          \"path\": \"$K3S_CNI_DIR\",
          \"type\": \"Directory\"
        }
      },
      {
        \"name\": \"cnibin\",
        \"hostPath\": {
          \"path\": \"$CNIBIN_PATH\",
          \"type\": \"Directory\"
        }
      }
    ]
  }
]" 2>&1

if [ $? -eq 0 ]; then
    echo_info "  ✓ DaemonSet 已更新"
else
    echo_error "  ✗ 更新失败"
    exit 1
fi

# 5. 删除旧 Pod 让其重新创建
echo ""
echo_info "5. 重启 Multus Pod"
echo ""

MULTUS_PODS=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_PODS" ]; then
    echo_info "  删除现有 Pod..."
    for pod in $MULTUS_PODS; do
        kubectl delete pod -n $NAMESPACE "$pod" --force --grace-period=0 2>/dev/null || true
        echo_info "    ✓ 已删除: $pod"
    done
    
    echo_info "  ✓ 等待 Pod 重新创建..."
    sleep 10
else
    echo_warn "  未找到 Multus Pod"
fi

# 6. 验证修复
echo ""
echo_info "6. 验证修复结果"
echo ""

sleep 5

echo_info "  新的 DaemonSet 配置:"
NEW_CNI_VOLUME=$(kubectl get daemonset -n $NAMESPACE $MULTUS_DS -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
NEW_CNI_MOUNT=$(kubectl get daemonset -n $NAMESPACE $MULTUS_DS -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

echo_info "    主机路径: $NEW_CNI_VOLUME"
echo_info "    Pod 内挂载点: $NEW_CNI_MOUNT"

if [ "$NEW_CNI_VOLUME" = "$K3S_CNI_DIR" ]; then
    echo_info "  ✓ 挂载路径已修复"
else
    echo_error "  ✗ 挂载路径修复失败"
fi

echo ""
echo_info "  检查 Pod 状态:"
kubectl get pods -n $NAMESPACE -l app=multus 2>/dev/null || echo_warn "  未找到 Pod"

echo ""
echo_info "  等待 Pod 启动并查看日志..."
sleep 10

MULTUS_POD=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod: $MULTUS_POD"
    
    # 检查 Pod 内文件
    if kubectl exec -n $NAMESPACE $MULTUS_POD -- test -f /host/etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null; then
        echo_info "    ✓ Pod 内可以访问配置文件"
    else
        echo_error "    ✗ Pod 内仍然无法访问配置文件"
    fi
    
    echo ""
    echo_info "  查看最新日志:"
    kubectl logs -n $NAMESPACE $MULTUS_POD --tail=20 2>&1 | head -15 || echo_warn "  无法获取日志"
else
    echo_warn "  等待 Pod 创建..."
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 仍然有问题，请检查："
echo "  1. 文件权限: sudo ls -la $CONFIG_FILE"
echo "  2. DaemonSet 配置: kubectl get daemonset -n $NAMESPACE $MULTUS_DS -o yaml"
echo "  3. Pod 详情: kubectl describe pod -n $NAMESPACE -l app=multus"
echo ""

