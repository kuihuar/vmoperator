#!/bin/bash

# 完整诊断 PVC Pending 问题

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
echo_info "完整诊断 PVC Pending 问题"
echo_info "=========================================="
echo ""

# 1. 检查 PVC 状态
echo_info "1. 检查 PVC 状态"
echo ""

PVC_LIST=$(kubectl get pvc --all-namespaces 2>/dev/null || echo "")

if [ -z "$PVC_LIST" ]; then
    echo_warn "  ⚠️  未找到任何 PVC"
else
    echo "$PVC_LIST"
    echo ""
    
    PENDING_PVC=$(echo "$PVC_LIST" | grep -v "Bound" | grep -v "NAME" || echo "")
    if [ -n "$PENDING_PVC" ]; then
        echo_warn "  ⚠️  发现未绑定的 PVC:"
        echo "$PENDING_PVC"
    fi
fi

echo ""

# 2. 检查 PV
echo_info "2. 检查 PV"
echo ""

PV_LIST=$(kubectl get pv 2>/dev/null || echo "")

if [ -z "$PV_LIST" ] || echo "$PV_LIST" | grep -q "No resources"; then
    echo_error "  ✗ 没有 PV 存在"
    echo_warn "    这是问题的根源 - CSI Provisioner 没有创建 PV"
else
    echo "$PV_LIST"
fi

echo ""

# 3. 检查 StorageClass
echo_info "3. 检查 StorageClass 配置"
echo ""

SC_NAME="rook-ceph-block"

if kubectl get storageclass "$SC_NAME" &>/dev/null; then
    echo_info "  ✓ StorageClass 存在: $SC_NAME"
    echo ""
    
    echo_info "  StorageClass 完整配置:"
    kubectl get storageclass "$SC_NAME" -o yaml
    echo ""
    
    # 检查关键参数
    PROVISIONER=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.provisioner}' 2>/dev/null || echo "")
    POOL=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.pool}' 2>/dev/null || echo "")
    CLUSTER_ID=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.clusterID}' 2>/dev/null || echo "")
    SECRET_NAME=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.csi.storage.k8s.io/provisioner-secret-name}' 2>/dev/null || echo "")
    SECRET_NAMESPACE=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.parameters.csi.storage.k8s.io/provisioner-secret-namespace}' 2>/dev/null || echo "")
    
    echo_info "  关键参数:"
    echo "    Provisioner: $PROVISIONER"
    echo "    Pool: $POOL"
    echo "    ClusterID: $CLUSTER_ID"
    echo "    Secret Name: $SECRET_NAME"
    echo "    Secret Namespace: $SECRET_NAMESPACE"
    echo ""
    
    if [ -z "$SECRET_NAME" ] || [ -z "$SECRET_NAMESPACE" ]; then
        echo_error "  ✗ Secret 配置缺失！这是导致 PVC 无法绑定的主要原因"
    fi
else
    echo_error "  ✗ StorageClass 不存在"
fi

echo ""

# 4. 检查 CSI Secret
echo_info "4. 检查 CSI Secret"
echo ""

if [ -n "$SECRET_NAME" ] && [ -n "$SECRET_NAMESPACE" ]; then
    if kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" &>/dev/null; then
        echo_info "  ✓ CSI Secret 存在: $SECRET_NAME (namespace: $SECRET_NAMESPACE)"
        echo ""
        
        SECRET_KEYS=$(kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")
        echo_info "  Secret Keys:"
        echo "$SECRET_KEYS" | while read key; do
            if [ -n "$key" ]; then
                echo "    - $key"
            fi
        done
    else
        echo_error "  ✗ CSI Secret 不存在: $SECRET_NAME (namespace: $SECRET_NAMESPACE)"
        echo_warn "    这是导致 PVC 无法绑定的主要原因"
    fi
else
    echo_warn "  ⚠️  无法检查 Secret（StorageClass 中未配置）"
fi

echo ""

# 5. 检查 CSI Provisioner Pods
echo_info "5. 检查 CSI Provisioner Pods"
echo ""

CSI_PROV_PODS=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner 2>/dev/null || echo "")

if [ -z "$CSI_PROV_PODS" ]; then
    echo_error "  ✗ 未找到 CSI Provisioner Pods"
    echo_warn "    这会导致 PVC 无法创建 PV"
else
    echo "$CSI_PROV_PODS"
    echo ""
    
    RUNNING_PROV=$(echo "$CSI_PROV_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_PROV" -eq 0 ]; then
        echo_error "  ✗ 没有运行中的 CSI Provisioner Pod"
        echo ""
        echo_info "  检查失败的 Pod 状态:"
        FAILED_POD=$(echo "$CSI_PROV_PODS" | grep -v "Running" | grep -v "NAME" | head -1 | awk '{print $1}')
        if [ -n "$FAILED_POD" ]; then
            kubectl describe pod "$FAILED_POD" -n rook-ceph | grep -A 20 "Events:" || echo "  无事件"
        fi
    else
        echo_info "  ✓ 有 $RUNNING_PROV 个 Provisioner Pod 正在运行"
        
        # 检查日志
        PROV_POD=$(echo "$CSI_PROV_PODS" | grep Running | head -1 | awk '{print $1}')
        if [ -n "$PROV_POD" ]; then
            echo ""
            echo_info "  检查 Provisioner Pod 日志（最后 30 行，查找错误）:"
            kubectl logs "$PROV_POD" -n rook-ceph -c csi-rbdplugin-provisioner --tail=30 2>&1 | grep -i "error\|fail\|secret\|auth" || echo "  未找到明显错误"
        fi
    fi
fi

echo ""

# 6. 检查 Ceph 存储池
echo_info "6. 检查 Ceph 存储池"
echo ""

if [ -n "$POOL" ]; then
    TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")
    
    if [ -n "$TOOLS_POD" ]; then
        POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null || echo "")
        
        if echo "$POOLS" | grep -q "^${POOL}$"; then
            echo_info "  ✓ 存储池 $POOL 存在"
        else
            echo_error "  ✗ 存储池 $POOL 不存在"
            echo_warn "    需要创建存储池: ./scripts/create-ceph-pool.sh $POOL"
        fi
    else
        echo_warn "  ⚠️  Tools Pod 不存在，无法检查存储池"
    fi
else
    echo_warn "  ⚠️  StorageClass 中未配置 pool 参数"
fi

echo ""

# 7. 检查 PVC 事件
echo_info "7. 检查 PVC 事件"
echo ""

PENDING_PVC_NAMES=$(echo "$PVC_LIST" | grep "Pending" | awk '{print $2}' | head -3)

if [ -n "$PENDING_PVC_NAMES" ]; then
    FIRST_PVC=$(echo "$PENDING_PVC_NAMES" | head -1)
    PVC_NS=$(echo "$PVC_LIST" | grep "$FIRST_PVC" | awk '{print $1}')
    
    echo_info "  检查 PVC 事件: $FIRST_PVC (namespace: $PVC_NS)"
    echo ""
    kubectl describe pvc "$FIRST_PVC" -n "$PVC_NS" | grep -A 30 "Events:" || echo "  无事件"
fi

echo ""

# 8. 总结
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

ISSUES=0

if [ -z "$PV_LIST" ] || echo "$PV_LIST" | grep -q "No resources"; then
    echo_error "[问题 $((++ISSUES))] 没有 PV 存在 - CSI Provisioner 未创建 PV"
fi

if [ -z "$SECRET_NAME" ] || [ -z "$SECRET_NAMESPACE" ]; then
    echo_error "[问题 $((++ISSUES))] StorageClass 中缺少 Secret 配置"
fi

if [ -n "$SECRET_NAME" ] && [ -n "$SECRET_NAMESPACE" ]; then
    if ! kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" &>/dev/null; then
        echo_error "[问题 $((++ISSUES))] CSI Secret 不存在: $SECRET_NAME (namespace: $SECRET_NAMESPACE)"
    fi
fi

RUNNING_PROV=$(echo "$CSI_PROV_PODS" | grep -c "Running" || echo "0")
if [ "$RUNNING_PROV" -eq 0 ]; then
    echo_error "[问题 $((++ISSUES))] CSI Provisioner Pod 未运行"
fi

if [ "$ISSUES" -eq 0 ]; then
    echo_info "  未发现明显问题"
    echo ""
    echo_info "  如果 PVC 仍然无法绑定，请检查:"
    echo "    1. CSI Provisioner 详细日志"
    echo "    2. Ceph 集群状态"
    echo "    3. 存储池配置"
else
    echo ""
    echo_info "  修复建议:"
    echo "    运行: ./scripts/fix-ceph-csi-secret.sh"
fi

echo ""

