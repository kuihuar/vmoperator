#!/bin/bash

# 立即修复 StorageClass Secret 配置

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
echo_info "立即修复 StorageClass Secret 配置"
echo_info "=========================================="
echo ""

SC_NAME="rook-ceph-block"

# 1. 检查当前 StorageClass 配置
echo_info "1. 检查当前 StorageClass 配置"
echo ""

kubectl get storageclass "$SC_NAME" -o yaml > /tmp/sc-current.yaml

echo_info "  当前 StorageClass 配置:"
cat /tmp/sc-current.yaml | grep -A 20 "parameters:" || echo "  未找到 parameters"
echo ""

# 检查是否有 Secret 配置
HAS_SECRET=$(grep -c "provisioner-secret" /tmp/sc-current.yaml || echo "0")

if [ "$HAS_SECRET" -gt 0 ]; then
    echo_info "  ✓ StorageClass 已有 Secret 配置"
    # 使用 jsonpath 更可靠地获取值
    SECRET_NAME=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.csi\.storage\.k8s\.io/provisioner-secret-name}' 2>/dev/null | tr -d '\n\r ' || echo "")
    SECRET_NS=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.csi\.storage\.k8s\.io/provisioner-secret-namespace}' 2>/dev/null | tr -d '\n\r ' || echo "")
    echo_info "    Secret Name: '$SECRET_NAME'"
    echo_info "    Secret Namespace: '$SECRET_NS'"
    
    # 检查 Secret 是否存在
    if [ -n "$SECRET_NAME" ] && [ -n "$SECRET_NS" ]; then
        if kubectl get secret "$SECRET_NAME" -n "$SECRET_NS" &>/dev/null; then
            echo_info "    ✓ Secret 存在"
            SECRET_DATA=$(kubectl get secret "$SECRET_NAME" -n "$SECRET_NS" -o jsonpath='{.data}' 2>/dev/null || echo "{}")
            if [ "$SECRET_DATA" = "{}" ]; then
                echo_warn "    ⚠️  Secret 内容为空，需要重新创建"
                CREATE_SECRET=true
            else
                CREATE_SECRET=false
            fi
        else
            echo_error "    ✗ Secret 不存在，需要创建"
            CREATE_SECRET=true
        fi
    else
        CREATE_SECRET=true
    fi
else
    echo_error "  ✗ StorageClass 缺少 Secret 配置"
    CREATE_SECRET=true
fi

echo ""

# 2. 创建或更新 CSI Secret
if [ "$CREATE_SECRET" = "true" ]; then
    echo_info "2. 创建 CSI Secret"
    echo ""
    
    # 获取 Ceph 认证信息
    CEPH_USER_SECRET="rook-ceph-mon"
    CEPH_ADMIN_SECRET="rook-ceph-admin-keyring"
    
    CEPH_USER=""
    CEPH_KEY=""
    
    # 尝试从 rook-ceph-mon 获取
    if kubectl get secret "$CEPH_USER_SECRET" -n rook-ceph &>/dev/null; then
        CEPH_USER=$(kubectl get secret "$CEPH_USER_SECRET" -n rook-ceph -o jsonpath='{.data.ceph-username}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        CEPH_KEY=$(kubectl get secret "$CEPH_USER_SECRET" -n rook-ceph -o jsonpath='{.data.ceph-secret}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    fi
    
    # 如果还是空的，尝试从 admin-keyring 获取
    if [ -z "$CEPH_KEY" ] && kubectl get secret "$CEPH_ADMIN_SECRET" -n rook-ceph &>/dev/null; then
        CEPH_KEY=$(kubectl get secret "$CEPH_ADMIN_SECRET" -n rook-ceph -o jsonpath='{.data.key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        CEPH_USER="admin"
    fi
    
    if [ -z "$CEPH_KEY" ]; then
        echo_error "  ✗ 无法获取 Ceph 密钥"
        echo_warn "    尝试从 client.admin 密钥环获取..."
        
        # 尝试从工具 Pod 获取
        TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")
        if [ -n "$TOOLS_POD" ]; then
            ADMIN_KEY=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph auth get-key client.admin 2>/dev/null || echo "")
            if [ -n "$ADMIN_KEY" ]; then
                CEPH_KEY="$ADMIN_KEY"
                CEPH_USER="admin"
                echo_info "  ✓ 从工具 Pod 获取到密钥"
            fi
        fi
    fi
    
    if [ -z "$CEPH_KEY" ]; then
        echo_error "  ✗ 无法获取 Ceph 认证信息"
        exit 1
    fi
    
    echo_info "  ✓ 获取到 Ceph 认证信息"
    echo "    用户: ${CEPH_USER:-admin}"
    echo "    密钥: ${CEPH_KEY:0:20}..."
    echo ""
    
    # 创建或更新 Secret
    if [ -z "$SECRET_NAME" ]; then
        SECRET_NAME="rook-csi-rbd-provisioner"
    fi
    if [ -z "$SECRET_NS" ]; then
        SECRET_NS="rook-ceph"
    fi
    
    # 清理变量中的换行符和空格
    SECRET_NAME=$(echo "$SECRET_NAME" | tr -d '\n' | tr -d ' ')
    SECRET_NS=$(echo "$SECRET_NS" | tr -d '\n' | tr -d ' ')
    
    echo_info "  创建 Secret: $SECRET_NAME (namespace: $SECRET_NS)"
    
    # 删除旧的 Secret（如果存在且为空）
    if kubectl get secret "$SECRET_NAME" -n "$SECRET_NS" &>/dev/null; then
        echo_info "  删除旧的 Secret..."
        kubectl delete secret "$SECRET_NAME" -n "$SECRET_NS" --ignore-not-found=true
    fi
    
    # 确保变量已清理
    SECRET_NAME=$(echo "$SECRET_NAME" | tr -d '\n\r\t ' | head -c 100)
    SECRET_NS=$(echo "$SECRET_NS" | tr -d '\n\r\t ' | head -c 100)
    
    if [ -z "$SECRET_NAME" ] || [ -z "$SECRET_NS" ]; then
        echo_error "  ✗ Secret 名称或命名空间为空"
        echo_error "    SECRET_NAME='$SECRET_NAME'"
        echo_error "    SECRET_NS='$SECRET_NS'"
        exit 1
    fi
    
    # 创建新的 Secret
    echo_info "  执行: kubectl create secret generic $SECRET_NAME -n $SECRET_NS"
    kubectl create secret generic "$SECRET_NAME" \
        --from-literal=userID="$CEPH_USER" \
        --from-literal=userKey="$CEPH_KEY" \
        -n "$SECRET_NS" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo_info "  ✓ Secret 已创建"
    echo ""
fi

# 3. 更新 StorageClass
echo_info "3. 更新 StorageClass"
echo ""

# 获取当前的 StorageClass 配置
SC_POOL=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.pool}' 2>/dev/null || echo "replicapool")
SC_CLUSTER_ID=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.clusterID}' 2>/dev/null || echo "rook-ceph")

if [ -z "$SC_POOL" ]; then
    SC_POOL="replicapool"
fi

if [ -z "$SC_CLUSTER_ID" ]; then
    SC_CLUSTER_ID="rook-ceph"
fi

if [ -z "$SECRET_NAME" ]; then
    SECRET_NAME="rook-csi-rbd-provisioner"
fi
if [ -z "$SECRET_NS" ]; then
    SECRET_NS="rook-ceph"
fi

# 清理变量中的换行符和空格
SECRET_NAME=$(echo "$SECRET_NAME" | tr -d '\n' | tr -d ' ')
SECRET_NS=$(echo "$SECRET_NS" | tr -d '\n' | tr -d ' ')

echo_info "  准备更新 StorageClass 参数:"
echo "    Pool: $SC_POOL"
echo "    ClusterID: $SC_CLUSTER_ID"
echo "    Secret Name: $SECRET_NAME"
echo "    Secret Namespace: $SECRET_NS"
echo ""

# 由于 StorageClass 的 parameters 是不可变的，需要删除后重新创建
echo_warn "  ⚠️  StorageClass parameters 不可修改，需要删除后重建"
echo_info "  备份当前 StorageClass..."
kubectl get storageclass "$SC_NAME" -o yaml > /tmp/sc-backup-$(date +%Y%m%d-%H%M%S).yaml

echo_info "  删除旧 StorageClass..."
kubectl delete storageclass "$SC_NAME"

echo_info "  创建新 StorageClass..."
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $SC_NAME
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: $SC_CLUSTER_ID
  pool: $SC_POOL
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: $SECRET_NAME
  csi.storage.k8s.io/provisioner-secret-namespace: $SECRET_NS
  csi.storage.k8s.io/controller-expand-secret-name: $SECRET_NAME
  csi.storage.k8s.io/controller-expand-secret-namespace: $SECRET_NS
  csi.storage.k8s.io/node-stage-secret-name: $SECRET_NAME
  csi.storage.k8s.io/node-stage-secret-namespace: $SECRET_NS
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF

echo_info "  ✓ StorageClass 已更新"
echo ""

# 4. 验证配置
echo_info "4. 验证配置"
echo ""

# 验证 Secret
if kubectl get secret "$SECRET_NAME" -n "$SECRET_NS" &>/dev/null; then
    echo_info "  ✓ Secret 存在: $SECRET_NAME"
else
    echo_error "  ✗ Secret 不存在"
fi

# 验证 StorageClass
if kubectl get storageclass "$SC_NAME" &>/dev/null; then
    echo_info "  ✓ StorageClass 存在: $SC_NAME"
    
    SC_SECRET_NAME=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.csi\.storage\.k8s\.io/provisioner-secret-name}' 2>/dev/null | tr -d '\n' | tr -d ' ' || echo "")
    if [ -n "$SC_SECRET_NAME" ]; then
        echo_info "  ✓ StorageClass 已配置 Secret: $SC_SECRET_NAME"
    else
        echo_error "  ✗ StorageClass 未配置 Secret"
    fi
else
    echo_error "  ✗ StorageClass 不存在"
fi

echo ""

# 5. 等待 PVC 绑定
echo_info "5. 等待 PVC 绑定（30秒）"
echo ""

sleep 10

PENDING_COUNT=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -c "Pending" || echo "0")
BOUND_COUNT=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -c "Bound" || echo "0")

echo_info "  PVC 状态: $PENDING_COUNT 个 Pending, $BOUND_COUNT 个 Bound"

if [ "$PENDING_COUNT" -gt 0 ]; then
    echo ""
    echo_info "  检查 PVC 事件:"
    PENDING_PVC=$(kubectl get pvc --all-namespaces 2>/dev/null | grep "Pending" | head -1)
    if [ -n "$PENDING_PVC" ]; then
        PVC_NS=$(echo "$PENDING_PVC" | awk '{print $1}')
        PVC_NAME=$(echo "$PENDING_PVC" | awk '{print $2}')
        kubectl describe pvc "$PVC_NAME" -n "$PVC_NS" | grep -A 10 "Events:" || echo "  无事件"
    fi
fi

echo ""

# 6. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "如果 PVC 仍然无法绑定，请检查:"
echo "  1. CSI Provisioner Pod 是否运行: kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner"
echo "  2. 存储池是否存在: ./scripts/check-ceph-pools.sh"
echo "  3. CSI Provisioner 日志: kubectl logs -n rook-ceph <provisioner-pod> -c csi-rbdplugin-provisioner"
echo ""

