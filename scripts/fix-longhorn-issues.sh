#!/bin/bash

# 修复 Longhorn 问题

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
echo_info "修复 Longhorn 问题"
echo_info "=========================================="
echo ""

# 1. 检查 longhorn-driver-deployer
echo_info "1. 检查 longhorn-driver-deployer"
echo ""

DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -n "$DRIVER_DEPLOYER" ]; then
    echo_info "  Pod: $DRIVER_DEPLOYER"
    echo ""
    
    # 获取 Pod 状态
    POD_STATUS=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    echo_info "  状态: $POD_STATUS"
    echo ""
    
    # 检查 init 容器
    INIT_CONTAINER=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].name}' 2>/dev/null || echo "")
    
    if [ -n "$INIT_CONTAINER" ]; then
        INIT_STATE=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null || echo "")
        INIT_READY=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].ready}' 2>/dev/null || echo "false")
        
        echo_info "  Init 容器: $INIT_CONTAINER"
        echo_info "  状态: $INIT_STATE"
        echo_info "  就绪: $INIT_READY"
        echo ""
        
        # 检查 init 容器日志
        echo_info "  Init 容器日志:"
        kubectl logs "$DRIVER_DEPLOYER" -n longhorn-system -c "$INIT_CONTAINER" --tail=50 2>&1 | head -50 || echo "  无法获取日志"
        echo ""
        
        # 检查等待原因
        WAITING_REASON=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
        if [ -n "$WAITING_REASON" ]; then
            echo_warn "  等待原因: $WAITING_REASON"
            WAITING_MSG=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].state.waiting.message}' 2>/dev/null || echo "")
            if [ -n "$WAITING_MSG" ]; then
                echo_warn "  等待消息: $WAITING_MSG"
            fi
        fi
    fi
    
    # 检查 Pod 事件
    echo_info "  Pod 事件:"
    kubectl describe pod "$DRIVER_DEPLOYER" -n longhorn-system | grep -A 30 "Events:" || echo "  无事件"
    echo ""
    
    # 检查是否是因为资源不足
    if echo "$POD_STATUS" | grep -q "Pending"; then
        echo_warn "  ⚠️  Pod 处于 Pending 状态，可能的原因："
        echo "    1. 节点资源不足（CPU/内存）"
        echo "    2. 节点选择器不匹配"
        echo "    3. 污点/容忍度问题"
        echo "    4. PVC 未绑定"
        echo ""
        
        # 检查调度信息
        UNSCHEDULABLE=$(kubectl get pod "$DRIVER_DEPLOYER" -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}' 2>/dev/null || echo "")
        if [ -n "$UNSCHEDULABLE" ]; then
            echo_warn "  调度问题: $UNSCHEDULABLE"
        fi
    fi
fi

echo ""

# 2. 检查 longhorn-manager
echo_info "2. 检查 longhorn-manager"
echo ""

MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -n "$MANAGER_POD" ]; then
    echo_info "  Pod: $MANAGER_POD"
    echo ""
    
    # 检查所有容器状态
    echo_info "  容器状态:"
    kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | tr ' ' '\n' | while read container; do
        if [ -n "$container" ]; then
            READY=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].ready}" 2>/dev/null || echo "false")
            RESTART_COUNT=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].restartCount}" 2>/dev/null || echo "0")
            STATE=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state}" 2>/dev/null || echo "")
            
            echo "    - $container:"
            echo "        Ready: $READY"
            echo "        Restarts: $RESTART_COUNT"
            echo "        State: $STATE"
            
            if [ "$READY" != "true" ]; then
                echo_warn "      ⚠️  容器未就绪"
                
                # 检查等待原因
                WAITING_REASON=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state.waiting.reason}" 2>/dev/null || echo "")
                if [ -n "$WAITING_REASON" ]; then
                    echo_warn "        等待原因: $WAITING_REASON"
                    WAITING_MSG=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state.waiting.message}" 2>/dev/null || echo "")
                    if [ -n "$WAITING_MSG" ]; then
                        echo_warn "        等待消息: $WAITING_MSG"
                    fi
                fi
                
                # 检查终止原因
                TERMINATED_REASON=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state.terminated.reason}" 2>/dev/null || echo "")
                if [ -n "$TERMINATED_REASON" ]; then
                    echo_warn "        终止原因: $TERMINATED_REASON"
                    TERMINATED_MSG=$(kubectl get pod "$MANAGER_POD" -n longhorn-system -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state.terminated.message}" 2>/dev/null || echo "")
                    if [ -n "$TERMINATED_MSG" ]; then
                        echo_warn "        终止消息: $TERMINATED_MSG"
                    fi
                fi
                
                # 显示容器日志
                echo_info "        容器日志（最后 30 行）:"
                kubectl logs "$MANAGER_POD" -n longhorn-system -c "$container" --tail=30 2>&1 | head -30 || echo "        无法获取日志"
            fi
        fi
    done
    echo ""
    
    # 检查 Pod 事件
    echo_info "  Pod 事件:"
    kubectl describe pod "$MANAGER_POD" -n longhorn-system | grep -A 30 "Events:" || echo "  无事件"
    echo ""
fi

# 3. 检查节点资源
echo_info "3. 检查节点资源"
echo ""

NODES=$(kubectl get nodes -o name 2>/dev/null || echo "")

if [ -n "$NODES" ]; then
    echo "$NODES" | while read node; do
        NODE_NAME=$(echo "$node" | sed 's|node/||')
        echo_info "  节点: $NODE_NAME"
        
        # 检查资源
        ALLOCATABLE_CPU=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.allocatable.cpu}' 2>/dev/null || echo "")
        ALLOCATABLE_MEM=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null || echo "")
        
        echo "    CPU: $ALLOCATABLE_CPU"
        echo "    内存: $ALLOCATABLE_MEM"
        
        # 检查磁盘空间
        DISK_PRESSURE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="DiskPressure")].status}' 2>/dev/null || echo "")
        MEMORY_PRESSURE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}' 2>/dev/null || echo "")
        PID_PRESSURE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="PIDPressure")].status}' 2>/dev/null || echo "")
        
        if [ "$DISK_PRESSURE" = "True" ]; then
            echo_warn "    ⚠️  磁盘压力: True"
        fi
        if [ "$MEMORY_PRESSURE" = "True" ]; then
            echo_warn "    ⚠️  内存压力: True"
        fi
        if [ "$PID_PRESSURE" = "True" ]; then
            echo_warn "    ⚠️  PID 压力: True"
        fi
    done
else
    echo_warn "  ⚠️  未找到节点"
fi

echo ""

# 4. 尝试修复建议
echo_info "4. 修复建议"
echo ""

echo_info "  根据检查结果，可能的修复方法："
echo ""
echo "  方法 1: 删除并重新创建 Pod（让 Kubernetes 重新调度）"
echo "    kubectl delete pod $DRIVER_DEPLOYER -n longhorn-system"
echo "    kubectl delete pod $MANAGER_POD -n longhorn-system"
echo ""
echo "  方法 2: 检查并修复资源问题"
echo "    - 确保节点有足够的 CPU 和内存"
echo "    - 检查节点是否有污点"
echo "    - 检查节点选择器配置"
echo ""
echo "  方法 3: 检查 Longhorn 配置"
echo "    kubectl get configmap -n longhorn-system"
echo "    kubectl get settings.longhorn.io -n longhorn-system"
echo ""
echo "  方法 4: 查看 Longhorn UI"
echo "    kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo "    然后访问 http://localhost:8080"
echo ""

# 5. 询问是否自动修复
echo_warn "  是否要尝试自动修复（删除并重新创建 Pod）？"
read -p "  输入 yes 继续，其他键跳过: " AUTO_FIX

if [ "$AUTO_FIX" = "yes" ]; then
    echo ""
    echo_info "  开始自动修复..."
    
    if [ -n "$DRIVER_DEPLOYER" ]; then
        echo_info "  删除 longhorn-driver-deployer Pod..."
        kubectl delete pod "$DRIVER_DEPLOYER" -n longhorn-system --ignore-not-found=true
    fi
    
    if [ -n "$MANAGER_POD" ]; then
        echo_info "  删除 longhorn-manager Pod..."
        kubectl delete pod "$MANAGER_POD" -n longhorn-system --ignore-not-found=true
    fi
    
    echo_info "  等待 Pod 重新创建（30秒）..."
    sleep 30
    
    echo_info "  检查新 Pod 状态:"
    kubectl get pods -n longhorn-system | grep -E "longhorn-driver-deployer|longhorn-manager"
else
    echo_info "  跳过自动修复"
fi

echo ""
echo_info "=========================================="
echo_info "检查完成"
echo_info "=========================================="
echo ""

