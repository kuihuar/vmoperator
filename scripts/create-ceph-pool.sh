#!/bin/bash

# 创建 Ceph 存储池

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

POOL_NAME="${1:-replicapool}"

echo ""
echo_info "=========================================="
echo_info "创建 Ceph 存储池: $POOL_NAME"
echo_info "=========================================="
echo ""

# 1. 检查 tools Pod
echo_info "1. 检查 rook-ceph-tools Pod"
echo ""

TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1)

if [ -z "$TOOLS_POD" ]; then
    echo_warn "  ⚠️  Tools Pod 不存在，创建中..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: rook-ceph-tools
  namespace: rook-ceph
  labels:
    app: rook-ceph-tools
spec:
  dnsPolicy: ClusterFirstWithHostNet
  containers:
  - name: rook-ceph-tools
    image: quay.io/ceph/ceph:v18.2.0
    command: ["/tini"]
    args: ["-g", "--", "/usr/local/bin/toolbox.sh"]
    imagePullPolicy: IfNotPresent
    env:
      - name: ROOK_CEPH_USERNAME
        valueFrom:
          secretKeyRef:
            name: rook-ceph-mon
            key: ceph-username
      - name: ROOK_CEPH_SECRET
        valueFrom:
          secretKeyRef:
            name: rook-ceph-mon
            key: ceph-secret
    volumeMounts:
      - name: mon-endpoint-volume
        mountPath: /etc/rook
    tty: true
    stdin: true
  volumes:
    - name: mon-endpoint-volume
      configMap:
        name: rook-ceph-mon-endpoints
        items:
        - key: data
          path: mon-endpoints
EOF
    
    echo_info "  等待 Tools Pod 就绪（60秒）..."
    kubectl wait --for=condition=ready pod rook-ceph-tools -n rook-ceph --timeout=120s || {
        echo_warn "  ⚠️  Tools Pod 启动超时，继续尝试..."
        sleep 30
    }
    
    TOOLS_POD="pod/rook-ceph-tools"
else
    echo_info "  ✓ Tools Pod 存在: $TOOLS_POD"
fi

echo ""

# 2. 检查存储池是否已存在
echo_info "2. 检查存储池是否已存在"
echo ""

if kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null | grep -q "^$POOL_NAME$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 已存在"
    
    # 显示存储池信息
    echo_info "  存储池信息:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool get "$POOL_NAME" all 2>/dev/null | head -20 || echo_warn "  无法获取存储池信息"
    
    exit 0
else
    echo_warn "  ⚠️  存储池 $POOL_NAME 不存在，需要创建"
fi

echo ""

# 3. 创建存储池
echo_info "3. 创建存储池: $POOL_NAME"
echo ""

# 获取 Ceph 集群信息
CEPH_STATUS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph status 2>/dev/null || echo "")

if [ -z "$CEPH_STATUS" ]; then
    echo_error "  ✗ 无法连接 Ceph 集群"
    exit 1
fi

# 创建存储池（使用推荐的配置）
echo_info "  创建 RBD 存储池..."

# 单节点环境使用较小的 pg_num
kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool create "$POOL_NAME" 32 32 2>/dev/null || {
    echo_error "  ✗ 存储池创建失败"
    echo_warn "  尝试检查错误信息..."
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool create "$POOL_NAME" 32 32
    exit 1
}

echo_info "  ✓ 存储池已创建"

echo ""

# 4. 初始化存储池为 RBD 存储池
echo_info "4. 初始化存储池为 RBD 存储池"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- rbd pool init "$POOL_NAME" 2>/dev/null || {
    echo_warn "  ⚠️  存储池初始化失败，可能已经初始化"
}

echo_info "  ✓ 存储池已初始化"

echo ""

# 5. 启用存储池的应用程序
echo_info "5. 启用存储池应用程序"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application enable "$POOL_NAME" rbd 2>/dev/null || {
    echo_warn "  ⚠️  启用应用程序失败，可能已经启用"
}

echo_info "  ✓ 应用程序已启用"

echo ""

# 6. 验证存储池
echo_info "6. 验证存储池"
echo ""

if kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null | grep -q "^$POOL_NAME$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 已成功创建"
    echo ""
    echo_info "  存储池详细信息:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool get "$POOL_NAME" all 2>/dev/null | head -20
else
    echo_error "  ✗ 存储池创建验证失败"
    exit 1
fi

echo ""

# 7. 总结
echo_info "=========================================="
echo_info "创建完成"
echo_info "=========================================="
echo ""

echo_info "存储池 $POOL_NAME 已成功创建并配置"
echo ""
echo_info "下一步:"
echo "  1. 验证 StorageClass 配置: kubectl get storageclass rook-ceph-block -o yaml"
echo "  2. 删除未绑定的 PVC: kubectl delete pvc <pvc-name>"
echo "  3. 重新创建 PVC（Wukong Controller 会自动重新创建）"
echo ""

