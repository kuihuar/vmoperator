#!/bin/bash

# 修复 Ceph Tools Pod 配置

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
echo_info "修复 Ceph Tools Pod 配置"
echo_info "=========================================="
echo ""

# 1. 删除现有的 Tools Pod
echo_info "1. 删除现有的 Tools Pod"
echo ""

if kubectl get pod rook-ceph-tools -n rook-ceph &>/dev/null; then
    echo_info "  删除现有 Pod..."
    kubectl delete pod rook-ceph-tools -n rook-ceph --wait=false
    echo_info "  ✓ Pod 已删除"
    
    # 等待 Pod 完全删除
    echo_info "  等待 Pod 删除（10秒）..."
    sleep 10
else
    echo_info "  Pod 不存在，直接创建"
fi

echo ""

# 2. 创建正确的 Tools Pod
echo_info "2. 创建正确的 Tools Pod"
echo ""

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

echo_info "  ✓ Pod 已创建"
echo ""

# 3. 等待 Pod 就绪
echo_info "3. 等待 Pod 就绪（最多 2 分钟）"
echo ""

for i in {1..24}; do
    POD_PHASE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    CONTAINER_READY=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    if [ "$POD_PHASE" = "Running" ] && [ "$CONTAINER_READY" = "true" ]; then
        echo_info "  ✓ Pod 已就绪"
        break
    fi
    
    if [ "$POD_PHASE" = "CrashLoopBackOff" ] || [ "$POD_PHASE" = "Error" ]; then
        echo_error "  ✗ Pod 启动失败: $POD_PHASE"
        echo_info "  查看 Pod 日志:"
        kubectl logs -n rook-ceph rook-ceph-tools --tail=30 2>&1 || echo "  无法获取日志"
        exit 1
    fi
    
    echo "  等待中... ($i/24)"
    sleep 5
done

echo ""

# 4. 测试连接
echo_info "4. 测试 Ceph 连接"
echo ""

if kubectl exec -n rook-ceph rook-ceph-tools -- echo "test" &>/dev/null; then
    echo_info "  ✓ 容器可以执行命令"
    
    # 测试 ceph 命令
    if kubectl exec -n rook-ceph rook-ceph-tools -- ceph status &>/dev/null; then
        echo_info "  ✓ Ceph 连接正常"
    else
        echo_warn "  ⚠️  Ceph 连接失败，但容器已就绪"
    fi
else
    echo_error "  ✗ 容器无法执行命令"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "现在可以创建存储池了:"
echo "  ./scripts/create-ceph-pool.sh replicapool"

