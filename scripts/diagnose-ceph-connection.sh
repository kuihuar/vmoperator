#!/bin/bash

# 诊断 Ceph 连接问题

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
echo_info "诊断 Ceph 连接问题"
echo_info "=========================================="
echo ""

# 1. 检查 Tools Pod
echo_info "1. 检查 rook-ceph-tools Pod"
echo ""

TOOLS_POD_STATUS=$(kubectl get pod rook-ceph-tools -n rook-ceph 2>/dev/null || echo "NotFound")

if [ "$TOOLS_POD_STATUS" = "NotFound" ]; then
    echo_error "  ✗ Tools Pod 不存在"
    echo_info "  创建 Tools Pod..."
    
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
    
    echo_info "  等待 Tools Pod 启动（60秒）..."
    sleep 60
else
    echo_info "  Tools Pod 状态:"
    kubectl get pod rook-ceph-tools -n rook-ceph
    echo ""
    
    POD_PHASE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$POD_PHASE" != "Running" ]; then
        echo_warn "  ⚠️  Pod 状态不是 Running: $POD_PHASE"
        echo ""
        echo_info "  Pod 事件:"
        kubectl describe pod rook-ceph-tools -n rook-ceph | grep -A 20 "Events:" || echo "  无事件"
    fi
fi

echo ""

# 2. 检查 Ceph 集群状态
echo_info "2. 检查 Ceph 集群状态"
echo ""

CEPH_CLUSTER=$(kubectl get cephcluster rook-ceph -n rook-ceph 2>/dev/null || echo "")

if [ -z "$CEPH_CLUSTER" ]; then
    echo_error "  ✗ Ceph 集群不存在"
    exit 1
fi

CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
CEPH_HEALTH=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "")

echo "  集群状态: $CEPH_PHASE"
echo "  健康状态: $CEPH_HEALTH"
echo ""

if [ "$CEPH_PHASE" != "Ready" ]; then
    echo_warn "  ⚠️  Ceph 集群未就绪"
fi

# 3. 检查 Mon Pods
echo_info "3. 检查 Mon Pods"
echo ""

MON_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-mon 2>/dev/null || echo "")

if [ -z "$MON_PODS" ]; then
    echo_error "  ✗ 未找到 Mon Pods"
    echo_warn "    没有 Mon，Ceph 集群无法正常工作"
else
    echo "$MON_PODS"
    echo ""
    
    RUNNING_MON=$(echo "$MON_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_MON" -gt 0 ]; then
        echo_info "  ✓ 有 $RUNNING_MON 个 Mon Pod 正在运行"
    else
        echo_warn "  ⚠️  没有运行中的 Mon Pod"
    fi
fi

echo ""

# 4. 检查 Mon endpoints ConfigMap
echo_info "4. 检查 Mon Endpoints ConfigMap"
echo ""

if kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph &>/dev/null; then
    echo_info "  ✓ Mon Endpoints ConfigMap 存在"
    echo ""
    echo_info "  Mon Endpoints 内容:"
    kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph -o jsonpath='{.data.data}' | tr ',' '\n' | head -5
else
    echo_error "  ✗ Mon Endpoints ConfigMap 不存在"
    echo_warn "    这会导致 Tools Pod 无法连接 Ceph"
fi

echo ""

# 5. 检查 Secret
echo_info "5. 检查 Ceph 认证 Secret"
echo ""

if kubectl get secret rook-ceph-mon -n rook-ceph &>/dev/null; then
    echo_info "  ✓ Ceph Mon Secret 存在"
else
    echo_error "  ✗ Ceph Mon Secret 不存在"
    echo_warn "    这会导致 Tools Pod 无法认证"
fi

echo ""

# 6. 检查 Pod 容器状态
echo_info "6. 检查 Pod 容器状态"
echo ""

POD_PHASE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
CONTAINER_READY=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
CONTAINER_NAME=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || echo "rook-ceph-tools")

echo "  Pod 状态: $POD_PHASE"
echo "  容器就绪: $CONTAINER_READY"
echo "  容器名称: $CONTAINER_NAME"
echo ""

if [ "$POD_PHASE" != "Running" ] || [ "$CONTAINER_READY" != "true" ]; then
    echo_warn "  ⚠️  Pod 或容器未就绪"
    echo_info "  查看 Pod 详细状态:"
    kubectl get pod rook-ceph-tools -n rook-ceph -o yaml | grep -A 20 "status:" | head -30
    echo ""
    echo_info "  查看 Pod 日志:"
    kubectl logs -n rook-ceph rook-ceph-tools --tail=30 2>&1 || echo "  无法获取日志"
    exit 1
fi

# 7. 尝试连接 Ceph
echo_info "7. 尝试连接 Ceph"
echo ""

echo_info "  执行 ceph status..."

# 等待几秒确保容器完全就绪
sleep 5

# 尝试执行 ceph status
CEPH_STATUS_OUTPUT=$(kubectl exec -n rook-ceph rook-ceph-tools -c "$CONTAINER_NAME" -- ceph status 2>&1)
CEPH_STATUS_EXIT=$?

if [ $CEPH_STATUS_EXIT -ne 0 ]; then
    echo_error "  ✗ ceph status 执行失败"
    echo ""
    echo_info "  错误输出:"
    echo "$CEPH_STATUS_OUTPUT"
    echo ""
    
    # 检查是否是容器未找到
    if echo "$CEPH_STATUS_OUTPUT" | grep -q "container not found"; then
        echo_warn "  容器未找到，尝试检查 Pod 状态:"
        kubectl get pod rook-ceph-tools -n rook-ceph -o yaml | grep -A 10 "containerStatuses"
        echo ""
        echo_info "  可能的原因:"
        echo "    1. Pod 还在启动中，请等待更长时间"
        echo "    2. 容器启动失败，查看 Pod 日志和事件"
        echo ""
        echo_info "  等待 30 秒后重试..."
        sleep 30
        CEPH_STATUS_OUTPUT=$(kubectl exec -n rook-ceph rook-ceph-tools -c "$CONTAINER_NAME" -- ceph status 2>&1)
        CEPH_STATUS_EXIT=$?
        
        if [ $CEPH_STATUS_EXIT -ne 0 ]; then
            echo_error "  重试后仍然失败"
            echo_info "  查看 Pod 日志:"
            kubectl logs -n rook-ceph rook-ceph-tools --tail=50 2>&1 || echo "  无法获取日志"
            exit 1
        fi
    else
        echo_info "  查看 Pod 日志:"
        kubectl logs -n rook-ceph rook-ceph-tools --tail=30 2>&1 || echo "  无法获取日志"
        exit 1
    fi
fi

echo_info "  ✓ Ceph 连接成功"
echo ""
echo "$CEPH_STATUS_OUTPUT" | head -30

echo ""
echo_info "=========================================="
echo_info "诊断完成"
echo_info "=========================================="

