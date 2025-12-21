#!/bin/bash

# 使用 Rook 在 k3s 上安装 Ceph 存储
# Rook 是 Kubernetes 原生的 Ceph 编排器，可以在 Kubernetes 中部署和管理 Ceph 集群

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
echo_info "使用 Rook 安装 Ceph 存储"
echo_info "=========================================="
echo ""

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo_error "kubectl 未安装"
    exit 1
fi

# 检查 Helm（可选，但推荐）
USE_HELM=true
if ! command -v helm &> /dev/null; then
    echo_warn "Helm 未安装，将使用 kubectl apply 方式"
    USE_HELM=false
fi

# 1. 添加 Helm Repository（如果使用 Helm）
if [ "$USE_HELM" = true ]; then
    echo ""
    echo_info "1. 配置 Helm Repository"
    echo ""
    
    helm repo add rook-release https://charts.rook.io/release 2>/dev/null || echo_warn "  Repository 可能已存在"
    helm repo update
    
    echo_info "  ✓ Helm Repository 已配置"
fi

# 2. 创建命名空间
echo ""
echo_info "2. 创建命名空间"
echo ""

kubectl create namespace rook-ceph --dry-run=client -o yaml | kubectl apply -f -
echo_info "  ✓ 命名空间已创建"

# 3. 安装 Rook Operator
echo ""
echo_info "3. 安装 Rook Operator"
echo ""

if [ "$USE_HELM" = true ]; then
    echo_info "  使用 Helm 安装..."
    
    helm install rook-ceph rook-release/rook-ceph \
        --namespace rook-ceph \
        --set operatorNamespace=rook-ceph \
        --wait \
        --timeout 10m
    
    if [ $? -eq 0 ]; then
        echo_info "  ✓ Rook Operator 已安装"
    else
        echo_error "  ✗ Rook Operator 安装失败"
        exit 1
    fi
else
    echo_info "  使用 kubectl apply 安装..."
    
    # 下载并应用 Rook Operator manifests
    ROOK_VERSION="v1.13.0"
    
    echo_info "  下载 CRDs..."
    kubectl apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/crds.yaml
    
    echo_info "  下载 Common manifests..."
    kubectl apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/common.yaml
    
    echo_info "  下载 Operator manifests..."
    kubectl apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/operator.yaml
    
    echo_info "  ✓ Rook Operator manifests 已应用"
    
    # 等待 Operator 就绪
    echo_info "  等待 Operator 就绪..."
    kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s || {
        echo_warn "  Operator 可能还在启动中，继续..."
    }
fi

# 4. 等待 Operator 就绪
echo ""
echo_info "4. 等待 Rook Operator 就绪"
echo ""

kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=600s || {
    echo_warn "  ⚠️  Operator 启动超时，检查状态..."
    kubectl get pods -n rook-ceph
}

echo_info "  ✓ Operator 已就绪"

# 5. 创建 Ceph Cluster
echo ""
echo_info "5. 创建 Ceph Cluster"
echo ""

echo_warn "  需要先准备存储设备或使用目录"
echo_info "  选择部署方式："
echo "    1. 使用所有可用设备（生产环境）"
echo "    2. 使用目录存储（开发/测试环境，单节点）"
echo ""

read -p "选择部署方式 (1/2，默认2): " DEPLOY_TYPE
DEPLOY_TYPE=${DEPLOY_TYPE:-2}

if [ "$DEPLOY_TYPE" = "2" ]; then
    echo_info "  创建基于目录的 Ceph Cluster（适用于开发/测试）"
    
    # 创建目录存储的 Ceph Cluster
    cat <<EOF | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1
  storage:
    useAllNodes: true
    useAllDevices: false
    config:
      databaseSizeMB: "1024"
      journalSizeMB: "1024"
    directories:
    - path: /var/lib/rook/ceph-data
EOF
    
    echo_info "  ✓ Ceph Cluster 配置已创建"
else
    echo_info "  创建基于设备的 Ceph Cluster"
    echo_warn "  需要手动创建 CephCluster CR，参考: config/ceph-cluster.yaml"
    echo_info "  或者继续使用默认配置..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1
  storage:
    useAllNodes: true
    useAllDevices: true
EOF
fi

# 6. 等待 Ceph Cluster 就绪
echo ""
echo_info "6. 等待 Ceph Cluster 就绪"
echo ""

echo_info "  这可能需要几分钟..."
for i in {1..60}; do
    if kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Ready"; then
        echo_info "  ✓ Ceph Cluster 已就绪"
        break
    fi
    echo "  等待中... ($i/60)"
    sleep 10
done

# 7. 安装 Ceph CSI Driver
echo ""
echo_info "7. 安装 Ceph CSI Driver"
echo ""

# Rook Operator 会自动安装 CSI Driver，但我们需要验证
kubectl wait --for=condition=ready pod -l app=csi-rbdplugin -n rook-ceph --timeout=300s || {
    echo_warn "  CSI Driver 可能还在启动中..."
}

# 8. 创建 StorageClass
echo ""
echo_info "8. 创建 StorageClass"
echo ""

cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

echo_info "  ✓ StorageClass 已创建"

# 设置为默认 StorageClass（可选）
read -p "是否设置为默认 StorageClass? (y/n) " SET_DEFAULT
if [[ $SET_DEFAULT =~ ^[Yy]$ ]]; then
    kubectl patch storageclass rook-ceph-block -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    echo_info "  ✓ 已设置为默认 StorageClass"
fi

# 9. 验证安装
echo ""
echo_info "9. 验证安装"
echo ""

sleep 10

echo_info "  Ceph Cluster 状态:"
kubectl get cephcluster -n rook-ceph

echo ""
echo_info "  Rook Pods:"
kubectl get pods -n rook-ceph

echo ""
echo_info "  StorageClass:"
kubectl get storageclass

echo ""
echo_info "  Ceph 状态:"
TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$TOOLS_POD" ]; then
    kubectl exec -n rook-ceph -it $TOOLS_POD -- ceph status 2>/dev/null || {
        echo_warn "  Ceph tools pod 可能还未就绪"
    }
else
    echo_warn "  Ceph tools pod 未找到，可能需要部署"
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "后续步骤:"
echo "  1. 等待所有 Pod 就绪: kubectl get pods -n rook-ceph -w"
echo "  2. 测试 PVC: kubectl apply -f config/ceph-test-pvc.yaml"
echo "  3. 参考文档: docs/CEPH_STORAGE.md"
echo ""

