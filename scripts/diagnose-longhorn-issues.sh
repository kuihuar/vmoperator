#!/bin/bash

# 详细诊断 Longhorn 问题

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
echo_info "详细诊断 Longhorn 问题"
echo_info "=========================================="
echo ""

# 1. 检查 longhorn-driver-deployer
echo_info "1. 检查 longhorn-driver-deployer"
echo ""

DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -n "$DRIVER_DEPLOYER" ]; then
    echo_info "  Pod: $DRIVER_DEPLOYER"
    echo ""
    
    # 检查 Pod 状态
    kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o wide
    echo ""
    
    # 检查 init 容器状态
    echo_info "  Init 容器状态:"
    kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[*].name}' 2>/dev/null | tr ' ' '\n' | while read container; do
        if [ -n "$container" ]; then
            STATE=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath="{.status.initContainerStatuses[?(@.name=='$container')].state}" 2>/dev/null || echo "")
            echo "    - $container: $STATE"
        fi
    done
    echo ""
    
    # 检查 init 容器日志
    INIT_CONTAINER=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].name}' 2>/dev/null || echo "")
    if [ -n "$INIT_CONTAINER" ]; then
        echo_info "  Init 容器日志 ($INIT_CONTAINER):"
        kubectl logs "$DRIVER_DEPLOYER" -n longhorn-system -c "$INIT_CONTAINER" --tail=30 2>&1 | head -30 || echo "  无法获取日志"
    fi
    echo ""
    
    # 检查 Pod 事件
    echo_info "  Pod 事件:"
    kubectl describe pod "$DRIVER_DEPLOYER" -n longhorn-system | grep -A 20 "Events:" || echo "  无事件"
    echo ""
fi

# 2. 检查 longhorn-manager
echo_info "2. 检查 longhorn-manager"
echo ""

MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -n "$MANAGER_POD" ]; then
    echo_info "  Pod: $MANAGER_POD"
    echo ""
    
    # 检查容器状态
    echo_info "  容器状态:"
    kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath='{.status.containerStatuses[*].name}' 2>/dev/null | tr ' ' '\n' | while read container; do
        if [ -n "$container" ]; then
            READY=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].ready}" 2>/dev/null || echo "false")
            STATE=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state}" 2>/dev/null || echo "")
            echo "    - $container: Ready=$READY, State=$STATE"
        fi
    done
    echo ""
    
    # 检查未就绪的容器日志
    NOT_READY_CONTAINERS=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath='{.status.containerStatuses[?(@.ready==false)].name}' 2>/dev/null || echo "")
    
    if [ -n "$NOT_READY_CONTAINERS" ]; then
        echo_warn "  未就绪的容器:"
        for container in $NOT_READY_CONTAINERS; do
            echo_info "    容器: $container"
            echo_info "    日志（最后 30 行）:"
            kubectl logs "$MANAGER_POD" -n longhorn-system -c "$container" --tail=30 2>&1 | head -30 || echo "    无法获取日志"
            echo ""
        done
    fi
    
    # 检查主容器日志（查找错误）
    echo_info "  主容器日志（查找错误，最后 50 行）:"
    kubectl logs "$MANAGER_POD" -n longhorn-system --tail=50 2>&1 | grep -i "error\|fail\|warn" | head -20 || echo "  未找到明显错误"
    echo ""
    
    # 检查 Pod 事件
    echo_info "  Pod 事件:"
    kubectl describe pod "$MANAGER_POD" -n longhorn-system | grep -A 20 "Events:" || echo "  无事件"
    echo ""
fi

# 3. 检查 StorageClass
echo_info "3. 检查 StorageClass"
echo ""

if ! kubectl get storageclass longhorn &>/dev/null; then
    echo_warn "  ⚠️  longhorn StorageClass 不存在"
    echo ""
    echo_info "  检查是否有其他 Longhorn 相关的 StorageClass:"
    kubectl get storageclass | grep -i longhorn || echo "  未找到"
    echo ""
    echo_info "  这可能是正常的，如果使用 Helm 安装，StorageClass 可能需要手动创建"
    echo_info "  或者检查 Longhorn UI 中的设置"
else
    echo_info "  ✓ longhorn StorageClass 存在"
    kubectl get storageclass longhorn -o yaml | head -30
fi

echo ""

# 4. 检查 Service
echo_info "4. 检查 Service"
echo ""

SERVICES=$(kubectl get svc -n longhorn-system 2>/dev/null || echo "")

if [ -z "$SERVICES" ]; then
    echo_warn "  ⚠️  未找到 Service"
    echo_info "  这可能是正常的，某些组件可能不需要 Service"
else
    echo "$SERVICES"
fi

echo ""

# 5. 检查节点标签和污点
echo_info "5. 检查节点配置"
echo ""

NODES=$(kubectl get nodes -o name 2>/dev/null || echo "")

if [ -n "$NODES" ]; then
    echo "$NODES" | while read node; do
        NODE_NAME=$(echo "$node" | sed 's|node/||')
        echo_info "  节点: $NODE_NAME"
        
        # 检查标签
        LABELS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels}' 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("longhorn")) | "\(.key)=\(.value)"' 2>/dev/null || echo "")
        if [ -n "$LABELS" ]; then
            echo "    标签: $LABELS"
        fi
        
        # 检查污点
        TAINTS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null || echo "")
        if [ -n "$TAINTS" ]; then
            echo "    污点: $TAINTS"
        fi
    done
else
    echo_warn "  ⚠️  未找到节点"
fi

echo ""

# 6. 检查资源限制
echo_info "6. 检查资源使用情况"
echo ""

if [ -n "$MANAGER_POD" ]; then
    echo_info "  longhorn-manager 资源使用:"
    kubectl top pod "$MANAGER_POD" -n longhorn-system 2>/dev/null || echo "  无法获取资源使用情况（需要 metrics-server）"
fi

echo ""

# 7. 检查 Longhorn 配置
echo_info "7. 检查 Longhorn 配置"
echo ""

CONFIGMAPS=$(kubectl get configmap -n longhorn-system 2>/dev/null | grep -i longhorn || echo "")

if [ -n "$CONFIGMAPS" ]; then
    echo "$CONFIGMAPS" | head -5
else
    echo_info "  未找到配置 ConfigMap"
fi

echo ""

# 8. 总结和建议
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

ISSUES=0

if [ -n "$DRIVER_DEPLOYER" ]; then
    DEPLOYER_STATUS=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$DEPLOYER_STATUS" != "Running" ]; then
        echo_error "[问题 $((++ISSUES))] longhorn-driver-deployer 未运行: $DEPLOYER_STATUS"
        echo_info "  解决: 检查 init 容器日志和 Pod 事件"
    fi
fi

if [ -n "$MANAGER_POD" ]; then
    MANAGER_READY=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")].ready}' 2>/dev/null || echo "false")
    if [ "$MANAGER_READY" != "true" ]; then
        echo_error "[问题 $((++ISSUES))] longhorn-manager 容器未就绪"
        echo_info "  解决: 检查容器日志和 Pod 事件"
    fi
fi

if ! kubectl get storageclass longhorn &>/dev/null; then
    echo_warn "[问题 $((++ISSUES))] StorageClass 不存在"
    echo_info "  解决: 通过 Longhorn UI 或 Helm values 创建 StorageClass"
fi

if [ "$ISSUES" -eq 0 ]; then
    echo_info "  未发现明显问题"
else
    echo ""
    echo_info "  建议操作:"
    echo "    1. 查看详细的 Pod 日志和事件"
    echo "    2. 检查节点资源（CPU、内存、磁盘）"
    echo "    3. 检查 Longhorn UI 访问: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
    echo "    4. 查看 Longhorn 文档: https://longhorn.io/docs/"
fi

echo ""

