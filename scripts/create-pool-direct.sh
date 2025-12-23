#!/bin/bash

# 直接使用 Secret 创建存储池

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

# 1. 获取 Ceph 认证信息
echo_info "1. 获取 Ceph 认证信息"
echo ""

CEPH_USER=$(kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data.ceph-username}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
CEPH_KEY=$(kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data.ceph-secret}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -z "$CEPH_USER" ] || [ -z "$CEPH_KEY" ]; then
    echo_error "  ✗ 无法获取 Ceph 认证信息"
    exit 1
fi

echo_info "  用户: $CEPH_USER"
echo_info "  密钥: ${CEPH_KEY:0:20}..."
echo ""

# 2. 获取 Mon endpoints
echo_info "2. 获取 Mon endpoints"
echo ""

MON_ENDPOINTS_RAW=$(kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph -o jsonpath='{.data.data}' 2>/dev/null || echo "")

if [ -z "$MON_ENDPOINTS_RAW" ]; then
    echo_error "  ✗ 无法获取 Mon endpoints"
    exit 1
fi

# 解析 Mon endpoints，提取 IP:PORT 格式
# 格式可能是: a=10.43.23.46:6789 或 a=10.43.23.46:6789,b=10.43.23.47:6789
MON_ENDPOINTS=$(echo "$MON_ENDPOINTS_RAW" | sed 's/[^=]*=\([0-9.]*:[0-9]*\)/\1/g' | tr ',' ' ' | awk '{print $1}')

if [ -z "$MON_ENDPOINTS" ]; then
    echo_error "  ✗ 无法解析 Mon endpoints"
    exit 1
fi

echo_info "  Mon endpoints (原始): $MON_ENDPOINTS_RAW"
echo_info "  Mon endpoints (解析后): $MON_ENDPOINTS"
echo ""

# 3. 确保 Tools Pod 存在
echo_info "3. 确保 Tools Pod 存在"
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
    
    echo_info "  等待 Pod 就绪（30秒）..."
    for i in {1..6}; do
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

# 4. 检查存储池是否已存在
echo_info "4. 检查存储池是否已存在"
echo ""

# 使用 ceph 命令检查，创建配置文件和 keyring
POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
cat > /tmp/ceph.conf <<EOF
[global]
mon_host = $MON_ENDPOINTS

[client.$CEPH_USER]
keyring = /tmp/keyring
EOF

cat > /tmp/keyring <<EOF
[$CEPH_USER]
key = $CEPH_KEY
EOF

export CEPH_CONF=/tmp/ceph.conf
ceph osd pool ls 2>/dev/null
" 2>&1 || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 已存在"
    exit 0
fi

echo ""

# 5. 创建存储池
echo_info "5. 创建存储池: $POOL_NAME"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
cat > /tmp/ceph.conf <<EOF
[global]
mon_host = $MON_ENDPOINTS

[client.$CEPH_USER]
keyring = /tmp/keyring
EOF

cat > /tmp/keyring <<EOF
[$CEPH_USER]
key = $CEPH_KEY
EOF

export CEPH_CONF=/tmp/ceph.conf
ceph osd pool create $POOL_NAME 32 32
" 2>&1 || {
    echo_warn "  ⚠️  创建命令执行失败，可能已存在"
}

echo ""

# 6. 初始化存储池
echo_info "6. 初始化存储池为 RBD"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
cat > /tmp/ceph.conf <<EOF
[global]
mon_host = $MON_ENDPOINTS

[client.$CEPH_USER]
keyring = /tmp/keyring
EOF

cat > /tmp/keyring <<EOF
[$CEPH_USER]
key = $CEPH_KEY
EOF

export CEPH_CONF=/tmp/ceph.conf
rbd pool init $POOL_NAME
" 2>&1 || {
    echo_warn "  ⚠️  初始化失败，可能已经初始化"
}

echo ""

# 7. 启用 rbd 应用程序
echo_info "7. 启用 rbd 应用程序"
echo ""

kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
cat > /tmp/ceph.conf <<EOF
[global]
mon_host = $MON_ENDPOINTS

[client.$CEPH_USER]
keyring = /tmp/keyring
EOF

cat > /tmp/keyring <<EOF
[$CEPH_USER]
key = $CEPH_KEY
EOF

export CEPH_CONF=/tmp/ceph.conf
ceph osd pool application enable $POOL_NAME rbd
" 2>&1 || {
    echo_warn "  ⚠️  启用失败，可能已经启用"
}

echo ""

# 8. 验证
echo_info "8. 验证存储池"
echo ""

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
cat > /tmp/ceph.conf <<EOF
[global]
mon_host = $MON_ENDPOINTS

[client.$CEPH_USER]
keyring = /tmp/keyring
EOF

cat > /tmp/keyring <<EOF
[$CEPH_USER]
key = $CEPH_KEY
EOF

export CEPH_CONF=/tmp/ceph.conf
ceph osd pool ls 2>/dev/null
" 2>&1 || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 创建成功"
    echo ""
    echo_info "  存储池信息:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
cat > /tmp/ceph.conf <<EOF
[global]
mon_host = $MON_ENDPOINTS

[client.$CEPH_USER]
keyring = /tmp/keyring
EOF

cat > /tmp/keyring <<EOF
[$CEPH_USER]
key = $CEPH_KEY
EOF

export CEPH_CONF=/tmp/ceph.conf
ceph osd pool get $POOL_NAME all 2>/dev/null | head -10
" 2>&1 || echo_warn "  无法获取详细信息"
else
    echo_error "  ✗ 存储池创建失败"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""

