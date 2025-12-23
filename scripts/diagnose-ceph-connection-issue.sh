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

# 1. 检查 Tools Pod 状态
echo_info "1. 检查 rook-ceph-tools Pod 状态"
echo ""

TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -z "$TOOLS_POD" ]; then
    echo_error "  ✗ Tools Pod 不存在"
    exit 1
fi

echo_info "  Pod: $TOOLS_POD"
echo ""

kubectl get pod "$TOOLS_POD" -n rook-ceph -o wide
echo ""

POD_PHASE=$(kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
CONTAINER_READY=$(kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

echo_info "  Pod 状态: $POD_PHASE"
echo_info "  容器就绪: $CONTAINER_READY"
echo ""

# 2. 检查 Pod 日志
echo_info "2. 检查 Pod 日志（最后 30 行）"
echo ""

kubectl logs -n rook-ceph "$TOOLS_POD" --tail=30 2>&1 || echo_warn "  无法获取日志"
echo ""

# 3. 检查 Pod 事件
echo_info "3. 检查 Pod 事件"
echo ""

kubectl describe pod "$TOOLS_POD" -n rook-ceph | grep -A 20 "Events:" || echo_warn "  无事件"
echo ""

# 4. 检查 Pod 配置
echo_info "4. 检查 Pod 配置"
echo ""

echo_info "  环境变量:"
kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.spec.containers[0].env[*].name}' 2>/dev/null | tr ' ' '\n' | while read var; do
    if [ -n "$var" ]; then
        echo "    - $var"
    fi
done
echo ""

echo_info "  Volume Mounts:"
kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.spec.containers[0].volumeMounts[*].mountPath}' 2>/dev/null | tr ' ' '\n' | while read mount; do
    if [ -n "$mount" ]; then
        echo "    - $mount"
    fi
done
echo ""

# 5. 检查 Mon Pods
echo_info "5. 检查 Mon Pods"
echo ""

MON_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-mon 2>/dev/null || echo "")

if [ -z "$MON_PODS" ]; then
    echo_error "  ✗ 未找到 Mon Pods"
else
    echo "$MON_PODS"
    echo ""
    
    RUNNING_MONS=$(echo "$MON_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_MONS" -gt 0 ]; then
        echo_info "  ✓ 有 $RUNNING_MONS 个 Mon Pod 正在运行"
    else
        echo_warn "  ⚠️  没有运行中的 Mon Pod"
    fi
fi

echo ""

# 6. 检查 ConfigMap
echo_info "6. 检查 rook-ceph-mon-endpoints ConfigMap"
echo ""

if kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph &>/dev/null; then
    echo_info "  ✓ ConfigMap 存在"
    echo ""
    echo_info "  ConfigMap 内容:"
    kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph -o yaml | grep -A 10 "data:" || echo_warn "  无法获取内容"
else
    echo_error "  ✗ ConfigMap 不存在"
fi

echo ""

# 7. 检查 Secret
echo_info "7. 检查 rook-ceph-mon Secret"
echo ""

if kubectl get secret rook-ceph-mon -n rook-ceph &>/dev/null; then
    echo_info "  ✓ Secret 存在"
    echo ""
    echo_info "  Secret Keys:"
    kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo_warn "  无法获取 keys"
else
    echo_error "  ✗ Secret 不存在"
fi

echo ""

# 8. 尝试执行命令
echo_info "8. 尝试在 Pod 中执行命令"
echo ""

if [ "$POD_PHASE" = "Running" ]; then
    echo_info "  测试基本命令执行:"
    if kubectl exec -n rook-ceph "$TOOLS_POD" -- echo "test" &>/dev/null; then
        echo_info "  ✓ 可以执行命令"
        echo ""
        
        echo_info "  测试 ceph 命令:"
        CEPH_STATUS_OUTPUT=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph status 2>&1)
        CEPH_STATUS_EXIT=$?
        
        if [ $CEPH_STATUS_EXIT -eq 0 ]; then
            echo_info "  ✓ ceph status 成功"
            echo "$CEPH_STATUS_OUTPUT" | head -20
        else
            echo_error "  ✗ ceph status 失败"
            echo ""
            echo_info "  错误输出:"
            echo "$CEPH_STATUS_OUTPUT"
            echo ""
            
            echo_info "  检查 ceph 命令是否存在:"
            kubectl exec -n rook-ceph "$TOOLS_POD" -- which ceph 2>&1 || echo_warn "  ceph 命令不存在"
            echo ""
            
            echo_info "  检查 /etc/rook 目录:"
            kubectl exec -n rook-ceph "$TOOLS_POD" -- ls -la /etc/rook 2>&1 || echo_warn "  无法访问 /etc/rook"
        fi
    else
        echo_error "  ✗ 无法执行命令"
    fi
else
    echo_warn "  ⚠️  Pod 未运行，无法测试"
fi

echo ""

# 9. 总结
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

echo_info "如果 Pod 无法连接到 Ceph，可能的原因："
echo ""
echo "1. Pod 配置错误（环境变量、Volume Mounts）"
echo "2. ConfigMap 或 Secret 不存在或配置错误"
echo "3. Mon Pods 未运行"
echo "4. 网络问题"
echo ""
echo_info "建议修复步骤："
echo "  1. 重新创建 Tools Pod: ./scripts/fix-ceph-tools-pod.sh"
echo "  2. 检查 Mon Pods: kubectl get pods -n rook-ceph -l app=rook-ceph-mon"
echo "  3. 检查 Ceph 集群: kubectl get cephcluster -n rook-ceph"
echo ""

