#!/bin/bash

# 卸载 Longhorn
# 参考: docs/UNINSTALL_LONGHORN.md

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
echo_info "卸载 Longhorn"
echo_info "=========================================="
echo ""

# 检查是否使用 Helm 安装
HELM_RELEASE=$(helm list -n longhorn-system 2>/dev/null | grep longhorn | awk '{print $1}' || echo "")

if [ -n "$HELM_RELEASE" ]; then
    echo_info "检测到 Helm 安装: $HELM_RELEASE"
    USE_HELM=true
else
    echo_info "未检测到 Helm 安装，使用 kubectl 方式卸载"
    USE_HELM=false
fi

# 确认卸载
echo ""
echo_warn "⚠️  警告：这将删除所有 Longhorn 数据和卷！"
    echo ""
read -p "确认要卸载 Longhorn 吗？(yes/no) " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo_warn "已取消"
    exit 0
fi

# 1. 使用 Helm 卸载
if [ "$USE_HELM" = true ]; then
    echo ""
    echo_info "1. 使用 Helm 卸载 Longhorn"
    echo ""
    
    helm uninstall $HELM_RELEASE -n longhorn-system --wait --timeout 5m 2>/dev/null || {
        echo_warn "  Helm 卸载可能不完整，继续使用 kubectl 清理"
    }
fi

# 2. 删除所有 Longhorn 资源
echo ""
echo_info "2. 删除 Longhorn 资源"
echo ""

echo_info "  删除所有 Longhorn Pods..."
kubectl delete pods -n longhorn-system --all --force --grace-period=0 --ignore-not-found=true

echo_info "  删除所有 Longhorn Deployments..."
kubectl delete deployment -n longhorn-system --all --ignore-not-found=true

echo_info "  删除所有 Longhorn DaemonSets..."
kubectl delete daemonset -n longhorn-system --all --ignore-not-found=true

echo_info "  删除所有 Longhorn StatefulSets..."
kubectl delete statefulset -n longhorn-system --all --ignore-not-found=true

echo_info "  删除所有 Longhorn Jobs..."
kubectl delete job -n longhorn-system --all --ignore-not-found=true --force --grace-period=0

echo_info "  删除所有 Longhorn Services..."
kubectl delete service -n longhorn-system --all --ignore-not-found=true

echo_info "  删除所有 Longhorn ConfigMaps..."
kubectl delete configmap -n longhorn-system --all --ignore-not-found=true

echo_info "  删除所有 Longhorn Secrets..."
kubectl delete secret -n longhorn-system --all --ignore-not-found=true

echo_info "  删除所有 Longhorn PVCs..."
kubectl delete pvc -n longhorn-system --all --ignore-not-found=true

# 3. 删除 CRDs
echo ""
echo_info "3. 删除 Longhorn CRDs"
echo ""

# 获取所有 Longhorn CRDs
LONGHORN_CRDS=$(kubectl get crd | grep longhorn | awk '{print $1}' || echo "")

if [ -n "$LONGHORN_CRDS" ]; then
    echo_info "  找到 Longhorn CRDs，删除中..."
    for crd in $LONGHORN_CRDS; do
        echo_info "    删除: $crd"
        kubectl delete crd $crd --ignore-not-found=true --wait=false
    done
else
    echo_info "  未找到 Longhorn CRDs"
fi

# 4. 删除 ClusterRole 和 ClusterRoleBinding
echo ""
echo_info "4. 删除 RBAC 资源"
echo ""

LONGHORN_RBAC=$(kubectl get clusterrole,clusterrolebinding | grep longhorn | awk '{print $1}' || echo "")
if [ -n "$LONGHORN_RBAC" ]; then
    for rbac in $LONGHORN_RBAC; do
        echo_info "  删除: $rbac"
        kubectl delete $rbac --ignore-not-found=true
    done
else
    echo_info "  未找到 Longhorn RBAC 资源"
fi

# 5. 删除 ServiceAccount
echo ""
echo_info "5. 删除 ServiceAccount"
echo ""

kubectl delete serviceaccount -n longhorn-system --all --ignore-not-found=true

# 6. 删除 StorageClass
echo ""
echo_info "6. 删除 StorageClass"
echo ""

LONGHORN_SC=$(kubectl get storageclass | grep longhorn | awk '{print $1}' || echo "")
if [ -n "$LONGHORN_SC" ]; then
    for sc in $LONGHORN_SC; do
        echo_info "  删除: $sc"
        kubectl delete storageclass $sc --ignore-not-found=true
    done
else
    echo_info "  未找到 Longhorn StorageClass"
fi

# 7. 删除命名空间（可选）
echo ""
echo_info "7. 删除命名空间"
echo ""

read -p "是否删除 longhorn-system 命名空间？(y/n) " DELETE_NS
if [[ $DELETE_NS =~ ^[Yy]$ ]]; then
    echo_info "  删除命名空间..."
    kubectl delete namespace longhorn-system --ignore-not-found=true --wait=true --timeout=5m 2>/dev/null || {
        echo_warn "  命名空间删除可能需要更多时间，正在强制删除..."
        kubectl delete namespace longhorn-system --ignore-not-found=true --grace-period=0 --force
    }
    echo_info "  ✓ 命名空间已删除"
else
    echo_info "  保留命名空间（可以稍后手动删除）"
fi

# 8. 清理节点上的数据（可选）
echo ""
echo_info "8. 清理节点数据（可选）"
echo ""

echo_warn "如果要完全清理，需要在每个节点上手动删除以下目录："
echo "  - /var/lib/longhorn/ (默认数据路径)"
echo "  - /mnt/longhorn/ (如果使用了自定义路径)"
echo ""
read -p "是否显示清理节点数据的命令？(y/n) " SHOW_CLEANUP
if [[ $SHOW_CLEANUP =~ ^[Yy]$ ]]; then
    echo ""
    echo_info "在每个节点上运行以下命令（需要 root 权限）："
    echo ""
    echo "  # 停止相关进程"
    echo "  sudo systemctl stop longhorn-engine longhorn-instance-manager longhorn-manager 2>/dev/null || true"
    echo ""
    echo "  # 删除数据目录"
    echo "  sudo rm -rf /var/lib/longhorn/*"
    echo "  sudo rm -rf /mnt/longhorn/* 2>/dev/null || true"
    echo ""
    echo "  # 清理 iSCSI（可选）"
    echo "  sudo iscsiadm -m session -P 3 | grep -i \"iqn.*longhorn\" | awk '{print \$3}' | xargs -r -n1 sudo iscsiadm -m node -u -T {} 2>/dev/null || true"
    echo ""
fi

# 9. 验证卸载
echo ""
echo_info "9. 验证卸载结果"
echo ""

sleep 5

REMAINING_PODS=$(kubectl get pods -n longhorn-system 2>/dev/null | grep -v NAME | wc -l || echo "0")
REMAINING_CRDS=$(kubectl get crd 2>/dev/null | grep longhorn | wc -l || echo "0")

if [ "$REMAINING_PODS" = "0" ] && [ "$REMAINING_CRDS" = "0" ]; then
    echo_info "  ✓ Longhorn 卸载完成"
else
    echo_warn "  ⚠️  仍有资源残留:"
    if [ "$REMAINING_PODS" != "0" ]; then
        echo_warn "    - Pods: $REMAINING_PODS"
        kubectl get pods -n longhorn-system 2>/dev/null || true
    fi
    if [ "$REMAINING_CRDS" != "0" ]; then
        echo_warn "    - CRDs: $REMAINING_CRDS"
        kubectl get crd | grep longhorn || true
    fi
fi

echo ""
echo_info "=========================================="
echo_info "卸载完成"
echo_info "=========================================="
echo ""
echo_info "如需重新安装，可以运行："
echo "  ./scripts/install-longhorn-helm.sh"
echo "  或参考: docs/LONGHORN_REINSTALL_GUIDE.md"
echo ""
