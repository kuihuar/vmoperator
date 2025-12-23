#!/bin/bash

# 修复 Ceph Tools Pod 连接问题

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
echo_info "修复 Ceph Tools Pod 连接问题"
echo_info "=========================================="
echo ""

# 1. 先运行诊断
echo_info "1. 运行诊断..."
echo ""

./scripts/diagnose-ceph-connection-issue.sh

echo ""

# 2. 检查必要的资源
echo_info "2. 检查必要的资源"
echo ""

# 检查 ConfigMap
if ! kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph &>/dev/null; then
    echo_error "  ✗ rook-ceph-mon-endpoints ConfigMap 不存在"
    echo_warn "    这可能是问题的根源"
    echo ""
    echo_info "  查找可用的 ConfigMap:"
    kubectl get configmap -n rook-ceph | grep -E "mon|ceph" || echo "  未找到相关 ConfigMap"
    echo ""
else
    echo_info "  ✓ rook-ceph-mon-endpoints ConfigMap 存在"
fi

# 检查 Secret
if ! kubectl get secret rook-ceph-mon -n rook-ceph &>/dev/null; then
    echo_error "  ✗ rook-ceph-mon Secret 不存在"
    echo_warn "    这可能是问题的根源"
    echo ""
    echo_info "  查找可用的 Secret:"
    kubectl get secret -n rook-ceph | grep -E "mon|ceph" || echo "  未找到相关 Secret"
    echo ""
else
    echo_info "  ✓ rook-ceph-mon Secret 存在"
fi

echo ""

# 3. 检查 Mon Pods
echo_info "3. 检查 Mon Pods"
echo ""

MON_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-mon 2>/dev/null || echo "")

if [ -z "$MON_PODS" ]; then
    echo_error "  ✗ 未找到 Mon Pods"
    echo_warn "    Ceph 集群可能未正确部署"
    exit 1
else
    RUNNING_MONS=$(echo "$MON_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_MONS" -eq 0 ]; then
        echo_error "  ✗ 没有运行中的 Mon Pod"
        echo_warn "    等待 Mon Pod 启动..."
        
        for i in {1..30}; do
            MON_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-mon 2>/dev/null || echo "")
            RUNNING_MONS=$(echo "$MON_PODS" | grep -c "Running" || echo "0")
            if [ "$RUNNING_MONS" -gt 0 ]; then
                echo_info "  ✓ Mon Pod 已启动"
                break
            fi
            echo "  等待中... ($i/30)"
            sleep 5
        done
    else
        echo_info "  ✓ 有 $RUNNING_MONS 个 Mon Pod 正在运行"
    fi
fi

echo ""

# 4. 查找正确的 ConfigMap 和 Secret 名称
echo_info "4. 查找正确的 ConfigMap 和 Secret 名称"
echo ""

# 查找包含 mon 的 ConfigMap
MON_ENDPOINTS_CM=$(kubectl get configmap -n rook-ceph -o name 2>/dev/null | grep -i mon | head -1 | sed 's|configmap/||' || echo "rook-ceph-mon-endpoints")

# 查找包含 mon 的 Secret
MON_SECRET=$(kubectl get secret -n rook-ceph -o name 2>/dev/null | grep -i "mon\|admin" | head -1 | sed 's|secret/||' || echo "rook-ceph-mon")

echo_info "  使用 ConfigMap: $MON_ENDPOINTS_CM"
echo_info "  使用 Secret: $MON_SECRET"
echo ""

# 5. 重新创建 Tools Pod（使用正确的配置）
echo_info "5. 重新创建 Tools Pod"
echo ""

# 删除现有 Pod
if kubectl get pod rook-ceph-tools -n rook-ceph &>/dev/null; then
    echo_info "  删除现有 Pod..."
    kubectl delete pod rook-ceph-tools -n rook-ceph --wait=false
    sleep 10
fi

# 检查 Secret 的 keys
SECRET_KEYS=$(kubectl get secret "$MON_SECRET" -n rook-ceph -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")

USERNAME_KEY="ceph-username"
SECRET_KEY="ceph-secret"

if echo "$SECRET_KEYS" | grep -q "admin-secret"; then
    SECRET_KEY="admin-secret"
fi

if echo "$SECRET_KEYS" | grep -q "admin-username"; then
    USERNAME_KEY="admin-username"
fi

echo_info "  使用 Secret keys: $USERNAME_KEY, $SECRET_KEY"
echo ""

# 创建新的 Pod（尝试多种配置）
echo_info "  创建新的 Tools Pod..."
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
            name: $MON_SECRET
            key: $USERNAME_KEY
      - name: ROOK_CEPH_SECRET
        valueFrom:
          secretKeyRef:
            name: $MON_SECRET
            key: $SECRET_KEY
    volumeMounts:
      - name: mon-endpoint-volume
        mountPath: /etc/rook
    tty: true
    stdin: true
  volumes:
    - name: mon-endpoint-volume
      configMap:
        name: $MON_ENDPOINTS_CM
        items:
        - key: data
          path: mon-endpoints
EOF

echo_info "  ✓ Pod 已创建"
echo ""

# 6. 等待 Pod 就绪
echo_info "6. 等待 Pod 就绪（最多 2 分钟）"
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
        echo ""
        echo_info "  查看 Pod 事件:"
        kubectl describe pod rook-ceph-tools -n rook-ceph | grep -A 10 "Events:" || echo "  无事件"
        exit 1
    fi
    
    echo "  等待中... ($i/24)"
    sleep 5
done

echo ""

# 7. 测试连接（使用多种方法）
echo_info "7. 测试 Ceph 连接"
echo ""

# 方法 1: 直接使用 ceph 命令
echo_info "  方法 1: 直接使用 ceph status"
if kubectl exec -n rook-ceph rook-ceph-tools -- ceph status &>/dev/null; then
    echo_info "  ✓ ceph status 成功"
    kubectl exec -n rook-ceph rook-ceph-tools -- ceph status 2>&1 | head -10
else
    echo_warn "  ⚠️  ceph status 失败"
    
    # 方法 2: 检查环境变量和配置文件
    echo_info "  方法 2: 检查环境变量"
    kubectl exec -n rook-ceph rook-ceph-tools -- env | grep -E "ROOK|CEPH" || echo_warn "  未找到相关环境变量"
    echo ""
    
    echo_info "  方法 3: 检查配置文件"
    kubectl exec -n rook-ceph rook-ceph-tools -- ls -la /etc/rook 2>&1 || echo_warn "  无法访问 /etc/rook"
    echo ""
    
    echo_info "  方法 4: 尝试使用 rookctl"
    if kubectl exec -n rook-ceph rook-ceph-tools -- which rookctl &>/dev/null; then
        echo_info "  ✓ rookctl 存在"
        kubectl exec -n rook-ceph rook-ceph-tools -- rookctl status 2>&1 | head -10 || echo_warn "  rookctl status 失败"
    else
        echo_warn "  ⚠️  rookctl 不存在"
    fi
    
    echo ""
    echo_warn "  ⚠️  无法连接到 Ceph，但 Pod 已就绪"
    echo_info "  可能需要手动配置或使用不同的连接方式"
fi

echo ""

# 8. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "如果仍然无法连接，请尝试："
echo "  1. 手动进入 Pod: kubectl exec -it -n rook-ceph rook-ceph-tools -- bash"
echo "  2. 检查环境变量: env | grep -E 'ROOK|CEPH'"
echo "  3. 检查配置文件: ls -la /etc/rook"
echo "  4. 尝试手动连接: ceph status"
echo ""

