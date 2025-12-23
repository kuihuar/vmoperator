#!/bin/bash

# 检查 Longhorn 安装状态

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
echo_info "检查 Longhorn 安装状态"
echo_info "=========================================="
echo ""

# 1. 检查命名空间
echo_info "1. 检查 longhorn-system 命名空间"
echo ""

if kubectl get namespace longhorn-system &>/dev/null; then
    echo_info "  ✓ longhorn-system 命名空间存在"
else
    echo_error "  ✗ longhorn-system 命名空间不存在"
    exit 1
fi

echo ""

# 2. 检查所有 Pod 状态
echo_info "2. 检查 Longhorn Pods 状态"
echo ""

PODS=$(kubectl get pods -n longhorn-system 2>/dev/null || echo "")

if [ -z "$PODS" ]; then
    echo_error "  ✗ 未找到任何 Pod"
    exit 1
fi

echo "$PODS"
echo ""

# 统计 Pod 状态
TOTAL_PODS=$(echo "$PODS" | grep -v "NAME" | wc -l | tr -d ' ')
RUNNING_PODS=$(echo "$PODS" | grep -c "Running" || echo "0")
PENDING_PODS=$(echo "$PODS" | grep -c "Pending" || echo "0")
FAILED_PODS=$(echo "$PODS" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | wc -l | tr -d ' ')

echo_info "  Pod 统计:"
echo "    总数: $TOTAL_PODS"
echo "    运行中: $RUNNING_PODS"
echo "    等待中: $PENDING_PODS"
echo "    失败: $FAILED_PODS"
echo ""

# 检查是否有失败的 Pod
if [ "$FAILED_PODS" -gt 0 ]; then
    echo_warn "  ⚠️  发现失败的 Pod:"
    echo "$PODS" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | while read line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        echo "    - $POD_NAME: $STATUS"
    done
    echo ""
fi

# 3. 检查关键组件
echo_info "3. 检查关键组件"
echo ""

# 检查 longhorn-manager
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager 2>/dev/null || echo "")
if [ -n "$MANAGER_PODS" ]; then
    RUNNING_MANAGERS=$(echo "$MANAGER_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_MANAGERS" -gt 0 ]; then
        echo_info "  ✓ longhorn-manager: $RUNNING_MANAGERS 个运行中"
    else
        echo_error "  ✗ longhorn-manager 未运行"
        echo "$MANAGER_PODS"
    fi
else
    echo_error "  ✗ 未找到 longhorn-manager Pod"
fi

# 检查 longhorn-ui
UI_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-ui 2>/dev/null || echo "")
if [ -n "$UI_PODS" ]; then
    RUNNING_UI=$(echo "$UI_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_UI" -gt 0 ]; then
        echo_info "  ✓ longhorn-ui: $RUNNING_UI 个运行中"
    else
        echo_warn "  ⚠️  longhorn-ui 未运行"
    fi
fi

# 检查 longhorn-csi-plugin
CSI_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-csi-plugin 2>/dev/null || echo "")
if [ -n "$CSI_PODS" ]; then
    RUNNING_CSI=$(echo "$CSI_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_CSI" -gt 0 ]; then
        echo_info "  ✓ longhorn-csi-plugin: $RUNNING_CSI 个运行中"
    else
        echo_warn "  ⚠️  longhorn-csi-plugin 未运行"
    fi
fi

echo ""

# 4. 检查失败的 Pod 日志
if [ "$FAILED_PODS" -gt 0 ]; then
    echo_info "4. 检查失败 Pod 的日志"
    echo ""
    
    FAILED_POD_NAMES=$(echo "$PODS" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | awk '{print $1}')
    
    for POD_NAME in $FAILED_POD_NAMES; do
        if [ -n "$POD_NAME" ]; then
            echo_warn "  Pod: $POD_NAME"
            echo_info "    最近日志（最后 20 行）:"
            kubectl logs "$POD_NAME" -n longhorn-system --tail=20 2>&1 | head -20 || echo "    无法获取日志"
            echo ""
        fi
    done
fi

# 5. 检查 Pod 事件
echo_info "5. 检查 Pod 事件（查找错误）"
echo ""

FAILED_POD_NAMES=$(echo "$PODS" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff|Pending" | awk '{print $1}' | head -3)

for POD_NAME in $FAILED_POD_NAMES; do
    if [ -n "$POD_NAME" ]; then
        echo_info "  Pod: $POD_NAME"
        EVENTS=$(kubectl describe pod "$POD_NAME" -n longhorn-system 2>/dev/null | grep -A 10 "Events:" || echo "")
        if [ -n "$EVENTS" ]; then
            echo "$EVENTS" | grep -i "error\|fail\|warning" | head -5 || echo "    无错误事件"
        fi
        echo ""
    fi
done

# 6. 检查 Multus 依赖
echo_info "6. 检查 Multus 依赖"
echo ""

# 检查 Pod 的网络注解
MULTUS_ANNOTATIONS=$(kubectl get pods -n longhorn-system -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations."k8s.v1.cni.cncf.io/networks" != null) | "\(.metadata.name): \(.metadata.annotations."k8s.v1.cni.cncf.io/networks")"' 2>/dev/null || echo "")

if [ -n "$MULTUS_ANNOTATIONS" ]; then
    echo_warn "  ⚠️  发现使用 Multus 的 Pod:"
    echo "$MULTUS_ANNOTATIONS" | while read line; do
        echo "    - $line"
    done
else
    echo_info "  ✓ 未发现 Multus 依赖（Pod 没有 Multus 网络注解）"
fi

# 检查是否有 NetworkAttachmentDefinition 引用
NAD_REF=$(kubectl get pods -n longhorn-system -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations."k8s.v1.cni.cncf.io/networks" != null) | .metadata.annotations."k8s.v1.cni.cncf.io/networks"' 2>/dev/null || echo "")

if [ -n "$NAD_REF" ]; then
    echo_warn "  ⚠️  发现 NetworkAttachmentDefinition 引用"
else
    echo_info "  ✓ 未发现 NetworkAttachmentDefinition 引用"
fi

echo ""

# 7. 检查 StorageClass
echo_info "7. 检查 StorageClass"
echo ""

if kubectl get storageclass longhorn &>/dev/null; then
    echo_info "  ✓ longhorn StorageClass 存在"
    kubectl get storageclass longhorn
else
    echo_warn "  ⚠️  longhorn StorageClass 不存在"
fi

echo ""

# 8. 检查 Service
echo_info "8. 检查 Service"
echo ""

SERVICES=$(kubectl get svc -n longhorn-system 2>/dev/null || echo "")

if [ -n "$SERVICES" ]; then
    echo "$SERVICES" | head -10
else
    echo_warn "  ⚠️  未找到 Service"
fi

echo ""

# 9. 检查 DaemonSet
echo_info "9. 检查 DaemonSet"
echo ""

DAEMONSETS=$(kubectl get daemonset -n longhorn-system 2>/dev/null || echo "")

if [ -n "$DAEMONSETS" ]; then
    echo "$DAEMONSETS"
else
    echo_warn "  ⚠️  未找到 DaemonSet"
fi

echo ""

# 10. 总结
echo_info "=========================================="
echo_info "检查总结"
echo_info "=========================================="
echo ""

if [ "$FAILED_PODS" -eq 0 ] && [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
    echo_info "  ✓ Longhorn 安装正常，所有 Pod 都在运行"
else
    echo_warn "  ⚠️  Longhorn 安装存在问题"
    echo ""
    echo_info "  建议检查:"
    echo "    1. 失败的 Pod 日志"
    echo "    2. Pod 事件"
    echo "    3. 节点资源（CPU、内存、磁盘）"
    echo "    4. 网络连接"
fi

if [ -z "$MULTUS_ANNOTATIONS" ]; then
    echo_info "  ✓ 未发现 Multus 依赖"
else
    echo_warn "  ⚠️  发现 Multus 依赖，可能需要移除"
fi

echo ""

