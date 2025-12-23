#!/bin/bash

# 安装 Longhorn（适用于单节点或多节点 k3s/k8s 集群）

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
echo_info "安装 Longhorn"
echo_info "=========================================="
echo ""

# ------------------------------------------
# 0. 前置检查：k3s / k8s 是否可用
# ------------------------------------------
if ! kubectl get nodes &>/dev/null; then
    echo_error "无法连接到 Kubernetes 集群（kubectl get nodes 失败）"
    echo_info "请先安装并配置好 k3s，再执行本脚本。"
    exit 1
fi

# ------------------------------------------
# 1. 检查是否已安装 Longhorn
# ------------------------------------------
if kubectl get ns longhorn-system &>/dev/null; then
    echo_warn "检测到已有 longhorn-system 命名空间，可能已安装 Longhorn。"
    kubectl get pods -n longhorn-system || true
    read -p "是否继续重新安装 Longhorn？(y/n，默认n): " REINSTALL
    REINSTALL=${REINSTALL:-n}
    if [[ ! $REINSTALL =~ ^[Yy]$ ]]; then
        echo_info "  跳过安装 Longhorn"
        exit 0
    fi
fi

# ------------------------------------------
# 2. 选择 Longhorn 版本（固定为 v1.8.1，k3s 官方文档示例版本）
# ------------------------------------------
LONGHORN_VERSION="v1.8.1"
echo_info "1. 使用固定 Longhorn 版本: ${LONGHORN_VERSION}"

# ------------------------------------------
# 3. 安装 Longhorn
# ------------------------------------------
echo ""
echo_info "2. 安装 Longhorn（版本: ${LONGHORN_VERSION}）..."

LONGHORN_URL="https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml"

echo_info "  使用 manifest: ${LONGHORN_URL}"

if kubectl apply -f "${LONGHORN_URL}" 2>&1; then
    echo_info "  ✓ Longhorn manifest 已应用"
else
    echo_error "  ✗ 应用 Longhorn manifest 失败"
    exit 1
fi

# ------------------------------------------
# 4. 等待 Longhorn Pod 就绪
# ------------------------------------------
echo ""
echo_info "3. 等待 Longhorn Pod 就绪（命名空间: longhorn-system，最长 10 分钟）..."

kubectl wait --for=condition=Available deployment -l app=longhorn-manager -n longhorn-system --timeout=600s 2>&1 \
    && echo_info "  ✓ longhorn-manager 已就绪" \
    || echo_warn "  ⚠️ longhorn-manager 等待超时，请检查 Pod 状态"

echo ""
echo_info "当前 Longhorn Pod 状态："
kubectl get pods -n longhorn-system

# ------------------------------------------
# 5. 检查 / 创建 StorageClass
# ------------------------------------------
echo ""
echo_info "4. 检查 Longhorn StorageClass..."

if kubectl get sc longhorn &>/dev/null; then
    echo_info "  ✓ 已存在 StorageClass: longhorn"
else
    echo_warn "  未发现名为 longhorn 的 StorageClass，尝试创建..."
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "30"
EOF
    echo_info "  ✓ 已创建 StorageClass: longhorn"
fi

echo ""
echo_info "5. 验证 StorageClass："
kubectl get sc | grep -i longhorn || echo_warn "  未找到 Longhorn StorageClass，请手动检查。"

# ------------------------------------------
# 6. 总结
# ------------------------------------------
echo ""
echo_info "=========================================="
echo_info "Longhorn 安装流程完成（版本: ${LONGHORN_VERSION}）"
echo_info "=========================================="
echo ""
echo_info "常用后续操作："
echo "  1. 访问 Longhorn UI:"
echo "     kubectl -n longhorn-system get svc longhorn-frontend"
echo "     kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80"
echo ""
echo_info "  2. 在 Wukong 中使用 Longhorn:"
echo "     在 Wukong CR 的 disks[*].storageClassName 中设置为: longhorn"
echo ""


