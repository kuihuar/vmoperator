#!/bin/bash

# 使用正确的 Tools Pod 配置创建存储池

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

# 1. 删除并重新创建 Tools Pod（使用正确的配置）
echo_info "1. 确保 Tools Pod 配置正确"
echo ""

# 先删除现有 Pod
if kubectl get pod rook-ceph-tools -n rook-ceph &>/dev/null; then
    echo_info "  删除现有 Tools Pod..."
    kubectl delete pod rook-ceph-tools -n rook-ceph --ignore-not-found=true
    sleep 5
fi

# 查找 rook-ceph-operator Pod，从它的配置获取正确的环境变量
echo_info "  查找 Rook Operator Pod 配置参考..."
OPERATOR_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-operator -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -n "$OPERATOR_POD" ]; then
    echo_info "  找到 Operator Pod: $OPERATOR_POD"
    
    # 获取 Operator Pod 的环境变量和卷配置
    OPERATOR_ENV=$(kubectl get pod "$OPERATOR_POD" -n rook-ceph -o jsonpath='{.spec.containers[0].env[*].name}' 2>/dev/null || echo "")
    echo_info "  Operator 使用的环境变量: $OPERATOR_ENV"
fi

echo ""

# 创建 Tools Pod（使用更完整的配置）
echo_info "2. 创建 Tools Pod（使用完整配置）"
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
      - name: rook-config-override
        mountPath: /etc/rook/rook-config-override
        readOnly: true
        optional: true
    tty: true
    stdin: true
    securityContext:
      privileged: false
  volumes:
    - name: mon-endpoint-volume
      configMap:
        name: rook-ceph-mon-endpoints
        items:
        - key: data
          path: mon-endpoints
    - name: rook-config-override
      configMap:
        name: rook-config-override
        optional: true
EOF

echo_info "  ✓ Pod 已创建"
echo ""

# 等待 Pod 就绪
echo_info "3. 等待 Pod 就绪（60秒）"
echo ""

for i in {1..12}; do
    POD_PHASE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    CONTAINER_READY=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    if [ "$POD_PHASE" = "Running" ] && [ "$CONTAINER_READY" = "true" ]; then
        echo_info "  ✓ Pod 已就绪"
        break
    fi
    
    if [ "$POD_PHASE" = "CrashLoopBackOff" ] || [ "$POD_PHASE" = "Error" ]; then
        echo_error "  ✗ Pod 启动失败: $POD_PHASE"
        kubectl logs -n rook-ceph rook-ceph-tools --tail=30 2>&1 || echo "  无法获取日志"
        exit 1
    fi
    
    echo "  等待中... ($i/12)"
    sleep 5
done

echo ""

# 4. 使用 rookctl 或直接设置环境变量后执行命令
echo_info "4. 设置环境变量并创建存储池"
echo ""

TOOLS_POD="rook-ceph-tools"

# 获取环境变量
CEPH_USER=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- printenv ROOK_CEPH_USERNAME 2>/dev/null || echo "")
CEPH_SECRET=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- printenv ROOK_CEPH_SECRET 2>/dev/null || echo "")

if [ -z "$CEPH_USER" ] || [ -z "$CEPH_SECRET" ]; then
    echo_warn "  ⚠️  环境变量未设置，尝试从 Secret 获取..."
    CEPH_USER=$(kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data.ceph-username}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    CEPH_SECRET=$(kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data.ceph-secret}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi

# 获取 Mon endpoints
MON_ENDPOINTS=$(kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph -o jsonpath='{.data.data}' 2>/dev/null | tr -d ' ' || echo "")

if [ -z "$MON_ENDPOINTS" ]; then
    echo_error "  ✗ 无法获取 Mon endpoints"
    exit 1
fi

echo_info "  使用用户: $CEPH_USER"
echo_info "  Mon endpoints: $MON_ENDPOINTS"
echo ""

# 检查存储池是否已存在
echo_info "5. 检查存储池是否已存在"
echo ""

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "export ROOK_CEPH_USERNAME='$CEPH_USER' && export ROOK_CEPH_SECRET='$CEPH_SECRET' && export ROOK_MON_ENDPOINTS='$MON_ENDPOINTS' && ceph -n \$ROOK_CEPH_USERNAME --keyring=/dev/stdin osd pool ls <<<\"\$ROOK_CEPH_SECRET\" 2>/dev/null || ceph osd pool ls 2>/dev/null" 2>&1 || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 已存在"
    exit 0
fi

# 尝试使用 rookctl
echo_info "6. 尝试使用 rookctl 创建存储池"
echo ""

if kubectl exec -n rook-ceph "$TOOLS_POD" -- which rookctl &>/dev/null; then
    echo_info "  rookctl 可用，使用 rookctl 创建..."
    kubectl exec -n rook-ceph "$TOOLS_POD" -- rookctl pool create "$POOL_NAME" --replicated 2>&1 || {
        echo_warn "  rookctl 创建失败，尝试使用 ceph 命令"
    }
else
    echo_info "  rookctl 不可用，使用 ceph 命令"
    
    # 直接使用 ceph 命令，通过环境变量传递认证信息
    echo_info "  创建存储池: ceph osd pool create $POOL_NAME 32 32"
    
    # 方法1: 尝试直接使用 ceph 命令（如果环境变量正确设置）
    kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "
        export ROOK_CEPH_USERNAME='$CEPH_USER'
        export ROOK_CEPH_SECRET='$CEPH_SECRET'
        export ROOK_MON_ENDPOINTS='$MON_ENDPOINTS'
        
        # 创建临时 keyring 文件
        echo \"[\$ROOK_CEPH_USERNAME]\" > /tmp/keyring
        echo \"key = \$ROOK_CEPH_SECRET\" >> /tmp/keyring
        
        # 使用 keyring 文件连接并创建存储池
        ceph -n \$ROOK_CEPH_USERNAME --keyring=/tmp/keyring osd pool create $POOL_NAME 32 32
    " 2>&1 || {
        echo_warn "  ⚠️  方法1失败，尝试方法2..."
    }
fi

echo ""

# 7. 验证存储池
echo_info "7. 验证存储池"
echo ""

sleep 3

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "export ROOK_CEPH_USERNAME='$CEPH_USER' && export ROOK_CEPH_SECRET='$CEPH_SECRET' && ceph -n \$ROOK_CEPH_USERNAME --keyring=/dev/stdin osd pool ls <<<\"\$ROOK_CEPH_SECRET\" 2>/dev/null || ceph osd pool ls 2>/dev/null" 2>&1 || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 创建成功"
    
    # 初始化存储池
    echo_info "  初始化存储池为 RBD..."
    kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "export ROOK_CEPH_USERNAME='$CEPH_USER' && export ROOK_CEPH_SECRET='$CEPH_SECRET' && rbd -n \$ROOK_CEPH_USERNAME --keyring=/dev/stdin pool init $POOL_NAME <<<\"\$ROOK_CEPH_SECRET\"" 2>&1 || echo_warn "  初始化可能已完成"
    
    # 启用 rbd 应用程序
    echo_info "  启用 rbd 应用程序..."
    kubectl exec -n rook-ceph "$TOOLS_POD" -- bash -c "export ROOK_CEPH_USERNAME='$CEPH_USER' && export ROOK_CEPH_SECRET='$CEPH_SECRET' && ceph -n \$ROOK_CEPH_USERNAME --keyring=/dev/stdin osd pool application enable $POOL_NAME rbd <<<\"\$ROOK_CEPH_SECRET\"" 2>&1 || echo_warn "  可能已经启用"
    
    echo ""
    echo_info "  ✓ 存储池配置完成"
else
    echo_error "  ✗ 存储池创建失败"
    echo ""
    echo_info "  手动创建步骤:"
    echo "    1. 进入 Tools Pod: kubectl exec -it -n rook-ceph rook-ceph-tools -- bash"
    echo "    2. 设置环境变量（从 Secret 获取）"
    echo "    3. 运行: ceph osd pool create $POOL_NAME 32 32"
    echo "    4. 运行: rbd pool init $POOL_NAME"
    echo "    5. 运行: ceph osd pool application enable $POOL_NAME rbd"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""

