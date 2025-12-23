#!/bin/bash

# 简单创建 Ceph 存储池

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

# 1. 检查 Tools Pod
echo_info "1. 检查 rook-ceph-tools Pod"
echo ""

TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

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
    image: rook/ceph:v1.13.0
    command: ["/bin/bash"]
    args: ["-c", "while true; do sleep 3600; done"]
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
    for i in {1..12}; do
        POD_PHASE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$POD_PHASE" = "Running" ]; then
            echo_info "  ✓ Pod 已就绪"
            break
        fi
        sleep 5
    done
    
    TOOLS_POD="rook-ceph-tools"
else
    echo_info "  ✓ Tools Pod 存在: $TOOLS_POD"
fi

echo ""

# 2. 检查存储池是否已存在
echo_info "2. 检查存储池是否已存在"
echo ""

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 已存在"
    exit 0
fi

echo_warn "  ⚠️  存储池 $POOL_NAME 不存在，创建中..."
echo ""

# 3. 创建存储池
echo_info "3. 创建存储池: $POOL_NAME"
echo ""

echo_info "  执行: ceph osd pool create $POOL_NAME 32 32"
POOL_CREATE_OUTPUT=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool create "$POOL_NAME" 32 32 2>&1 || echo "")
POOL_CREATE_EXIT=$?

if echo "$POOL_CREATE_OUTPUT" | grep -q "already exists\|EEXIST"; then
    echo_info "  ✓ 存储池已存在（之前创建）"
elif echo "$POOL_CREATE_OUTPUT" | grep -q "pool.*created"; then
    echo_info "  ✓ 存储池创建成功"
else
    echo "$POOL_CREATE_OUTPUT"
    if [ $POOL_CREATE_EXIT -ne 0 ]; then
        echo_error "  ✗ 存储池创建失败"
        exit 1
    fi
fi

echo ""

# 4. 初始化存储池
echo_info "4. 初始化存储池为 RBD 存储池"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- rbd pool init "$POOL_NAME" 2>&1 || {
    echo_warn "  ⚠️  初始化失败，可能已经初始化"
}

echo ""

# 5. 启用 rbd 应用程序
echo_info "5. 启用 rbd 应用程序"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application enable "$POOL_NAME" rbd 2>&1 || {
    echo_warn "  ⚠️  启用失败，可能已经启用"
}

echo ""

# 6. 验证
echo_info "6. 验证存储池"
echo ""

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 创建成功"
    echo ""
    echo_info "  存储池信息:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool get "$POOL_NAME" all 2>/dev/null | head -10 || echo_warn "  无法获取详细信息"
else
    echo_error "  ✗ 存储池创建验证失败"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""

