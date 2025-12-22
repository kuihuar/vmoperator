#!/bin/bash

# 创建包含 Secret 配置的 StorageClass

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SECRET_NAME="${1:-rook-csi-rbd-provisioner}"
SECRET_NAMESPACE="${2:-rook-ceph}"

echo ""
echo_info "创建 StorageClass（包含 Secret 配置）"
echo ""

# 创建临时 YAML 文件
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

cat > "$TEMP_FILE" <<EOF
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
  csi.storage.k8s.io/provisioner-secret-name: ${SECRET_NAME}
  csi.storage.k8s.io/provisioner-secret-namespace: ${SECRET_NAMESPACE}
  csi.storage.k8s.io/controller-expand-secret-name: ${SECRET_NAME}
  csi.storage.k8s.io/controller-expand-secret-namespace: ${SECRET_NAMESPACE}
  csi.storage.k8s.io/node-stage-secret-name: ${SECRET_NAME}
  csi.storage.k8s.io/node-stage-secret-namespace: ${SECRET_NAMESPACE}
  csi.storage.k8s.io/node-publish-secret-name: ${SECRET_NAME}
  csi.storage.k8s.io/node-publish-secret-namespace: ${SECRET_NAMESPACE}
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

echo_info "应用 StorageClass..."
kubectl apply -f "$TEMP_FILE"

echo_info "✓ StorageClass 已创建"
echo ""
echo_info "验证配置:"
kubectl get storageclass rook-ceph-block -o yaml | grep -A 2 "csi.storage.k8s.io/provisioner-secret-name"

