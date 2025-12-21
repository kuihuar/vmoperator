#!/bin/bash

# 彻底诊断 Multus kubeconfig 问题

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "彻底诊断 Multus kubeconfig 问题"
echo_info "=========================================="
echo ""

# 1. 检查主机上的文件
echo_info "1. 检查主机上的文件"
echo ""

POSSIBLE_PATHS=(
    "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
    "/etc/cni/net.d/multus.d/multus.kubeconfig"
)

FOUND_HOST_FILE=""
for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo_info "  ✓ 找到文件: $path"
        sudo ls -lh "$path"
        FOUND_HOST_FILE="$path"
        break
    else
        echo_warn "  ✗ 不存在: $path"
    fi
done

if [ -z "$FOUND_HOST_FILE" ]; then
    echo_error "  ✗ 所有可能的位置都没有找到文件！"
fi

# 2. 检查 DaemonSet 挂载配置
echo ""
echo_info "2. 检查 Multus DaemonSet 挂载配置"
echo ""

DS_NAME=$(kubectl get daemonset -n kube-system -o name | grep multus | head -1)
if [ -z "$DS_NAME" ]; then
    echo_error "  ✗ 未找到 Multus DaemonSet"
    exit 1
fi

echo_info "  DaemonSet: $DS_NAME"

DS_HOST_PATH=$(kubectl get $DS_NAME -n kube-system -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get $DS_NAME -n kube-system -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

echo_info "  主机路径: $DS_HOST_PATH"
echo_info "  Pod 内挂载点: $DS_MOUNT_PATH"

# 计算期望的主机文件路径
if [ -n "$DS_HOST_PATH" ] && [ -n "$DS_MOUNT_PATH" ]; then
    # 从 Pod 内路径 /host/etc/cni/net.d/multus.d/multus.kubeconfig
    # 计算主机路径
    EXPECTED_HOST_PATH="$DS_HOST_PATH/multus.d/multus.kubeconfig"
    echo_info "  期望的主机文件路径: $EXPECTED_HOST_PATH"
    
    if [ -f "$EXPECTED_HOST_PATH" ]; then
        echo_info "  ✓ 期望路径的文件存在"
    else
        echo_error "  ✗ 期望路径的文件不存在"
    fi
fi

# 3. 检查 Multus 配置文件
echo ""
echo_info "3. 检查 Multus 配置文件"
echo ""

MULTUS_CONF_PATHS=(
    "/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf"
    "/etc/cni/net.d/00-multus.conf"
)

MULTUS_CONF=""
for path in "${MULTUS_CONF_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo_info "  找到配置文件: $path"
        MULTUS_CONF="$path"
        
        KUBECONFIG_IN_CONF=$(sudo cat "$path" | jq -r '.kubeconfig // ""' 2>/dev/null || echo "")
        echo_info "  配置中指定的路径: ${KUBECONFIG_IN_CONF:-未配置}"
        break
    fi
done

if [ -z "$MULTUS_CONF" ]; then
    echo_warn "  ⚠️  未找到 Multus 配置文件"
fi

# 4. 检查 Multus Pod 状态
echo ""
echo_info "4. 检查 Multus Pod 状态"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$MULTUS_POD" ]; then
    echo_error "  ✗ 未找到 Multus Pod"
else
    echo_info "  Pod: $MULTUS_POD"
    
    POD_STATUS=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}')
    echo_info "  状态: $POD_STATUS"
    
    if [ "$POD_STATUS" = "Running" ]; then
        echo_info "  检查 Pod 内文件访问..."
        
        # 尝试多个可能的路径
        TEST_PATHS=(
            "/host/etc/cni/net.d/multus.d/multus.kubeconfig"
            "/etc/cni/net.d/multus.d/multus.kubeconfig"
        )
        
        for test_path in "${TEST_PATHS[@]}"; do
            echo_debug "    尝试: $test_path"
            if kubectl exec -n kube-system $MULTUS_POD -- test -f "$test_path" 2>/dev/null; then
                echo_info "    ✓ 可以访问: $test_path"
                kubectl exec -n kube-system $MULTUS_POD -- ls -lh "$test_path" 2>/dev/null
                break
            else
                echo_warn "    ✗ 无法访问: $test_path"
            fi
        done
        
        # 检查挂载点
        echo_info "  检查挂载点:"
        kubectl exec -n kube-system $MULTUS_POD -- ls -ld /host/etc/cni/net.d 2>/dev/null || echo_warn "    ✗ 无法访问挂载点"
        kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/multus.d 2>/dev/null || echo_warn "    ✗ multus.d 目录不存在"
    else
        echo_warn "  ⚠️  Pod 不是 Running 状态"
        echo_info "  最近的日志:"
        kubectl logs -n kube-system $MULTUS_POD --tail=10 2>&1 | head -5
    fi
fi

# 5. 诊断结果
echo ""
echo_info "5. 诊断结果"
echo ""

if [ -z "$FOUND_HOST_FILE" ]; then
    echo_error "  ✗ 问题：主机上找不到 kubeconfig 文件"
    echo_info "  解决方案："
    if [ -n "$DS_HOST_PATH" ]; then
        EXPECTED_PATH="$DS_HOST_PATH/multus.d/multus.kubeconfig"
        echo "    sudo mkdir -p $(dirname $EXPECTED_PATH)"
        echo "    sudo cp /etc/rancher/k3s/k3s.yaml $EXPECTED_PATH"
        echo "    sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' $EXPECTED_PATH"
        echo "    sudo chmod 644 $EXPECTED_PATH"
    else
        echo "    无法确定路径，请先检查 DaemonSet 配置"
    fi
elif [ -n "$DS_HOST_PATH" ] && [ "$FOUND_HOST_FILE" != "$EXPECTED_HOST_PATH" ]; then
    echo_warn "  ⚠️  问题：文件位置与期望路径不匹配"
    echo_info "  当前文件: $FOUND_HOST_FILE"
    echo_info "  期望路径: $EXPECTED_HOST_PATH"
    echo_info "  解决方案："
    echo "    sudo mkdir -p $(dirname $EXPECTED_HOST_PATH)"
    echo "    sudo cp $FOUND_HOST_FILE $EXPECTED_HOST_PATH"
    echo "    sudo chmod 644 $EXPECTED_HOST_PATH"
elif [ -n "$MULTUS_POD" ]; then
    POD_STATUS=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$POD_STATUS" != "Running" ]; then
        echo_warn "  ⚠️  问题：Multus Pod 未正常运行"
        echo_info "  解决方案：检查 Pod 日志并修复问题"
    else
        echo_info "  ✓ 文件存在，但 Pod 内无法访问"
        echo_info "  可能原因："
        echo "    1. 挂载配置不正确"
        echo "    2. 权限问题"
        echo "    3. Pod 需要重启"
        echo_info "  解决方案："
        echo "    kubectl delete pod -n kube-system $MULTUS_POD --force --grace-period=0"
    fi
fi

echo ""

