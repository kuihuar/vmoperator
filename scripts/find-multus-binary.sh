#!/bin/bash

# 查找 Multus CNI 插件二进制文件

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo_info "查找 Multus CNI 插件二进制文件"
echo ""

# 1. 检查 k3s 的 CNI 二进制目录
echo_info "1. 检查 k3s CNI 二进制目录"
echo ""

CNI_BIN_DIRS=(
    "/var/lib/rancher/k3s/data/current/bin"
    "/opt/cni/bin"
    "/var/lib/cni/bin"
    "/usr/local/bin"
)

for dir in "${CNI_BIN_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo_info "  目录: $dir"
        if [ -f "$dir/multus" ]; then
            echo_info "    ✓ 找到 multus 二进制: $dir/multus"
            ls -lh "$dir/multus"
        else
            echo_warn "    ✗ 未找到 multus"
        fi
    fi
done

# 2. 检查 DaemonSet 中安装的二进制
echo ""
echo_info "2. 检查 Multus DaemonSet 如何安装二进制"
echo ""

DS_NAME=$(kubectl get daemonset -n kube-system -o name | grep multus | head -1)
if [ -n "$DS_NAME" ]; then
    echo_info "  DaemonSet: $DS_NAME"
    
    # 检查 init 容器
    INIT_CONTAINER=$(kubectl get $DS_NAME -n kube-system -o jsonpath='{.spec.template.spec.initContainers[0].name}' 2>/dev/null || echo "")
    if [ -n "$INIT_CONTAINER" ]; then
        echo_info "  Init 容器: $INIT_CONTAINER"
        
        # 检查 init 容器的命令
        INIT_COMMAND=$(kubectl get $DS_NAME -n kube-system -o jsonpath='{.spec.template.spec.initContainers[0].command[*]}' 2>/dev/null || echo "")
        echo_info "  命令: $INIT_COMMAND"
        
        # 检查 volumeMounts
        INIT_MOUNT=$(kubectl get $DS_NAME -n kube-system -o jsonpath='{.spec.template.spec.initContainers[0].volumeMounts[?(@.name=="cnibin")].mountPath}' 2>/dev/null || echo "")
        echo_info "  挂载点: $INIT_MOUNT"
        
        # 检查对应的 hostPath
        CNI_BIN_HOST=$(kubectl get $DS_NAME -n kube-system -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cnibin")].hostPath.path}' 2>/dev/null || echo "")
        echo_info "  主机路径: $CNI_BIN_HOST"
        
        if [ -n "$CNI_BIN_HOST" ]; then
            echo ""
            echo_info "  检查主机路径:"
            if [ -d "$CNI_BIN_HOST" ]; then
                ls -lh "$CNI_BIN_HOST"/multus 2>/dev/null || echo_warn "    ✗ 未找到 multus"
            else
                echo_warn "    ✗ 目录不存在"
            fi
        fi
    fi
fi

# 3. 检查 k3s 的 CNI 配置
echo ""
echo_info "3. 检查 k3s CNI 配置"
echo ""

K3S_CNI_CONF="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if [ -d "$K3S_CNI_CONF" ]; then
    echo_info "  CNI 配置目录: $K3S_CNI_CONF"
    echo_info "  配置文件:"
    sudo ls -lh "$K3S_CNI_CONF"/*.conf 2>/dev/null | head -5 || echo_warn "    未找到配置文件"
fi

# 4. 检查 kubelet 如何调用 CNI
echo ""
echo_info "4. CNI 插件调用机制"
echo ""
echo_info "  当 kubelet 创建 Pod 时："
echo_info "    1. kubelet 读取 CNI 配置文件（/var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf）"
echo_info "    2. kubelet 调用 CNI 二进制（在主机上运行，不是 Pod 内）"
echo_info "    3. CNI 二进制读取配置文件中的路径（必须是主机路径）"
echo_info "    4. Multus CNI 插件需要 kubeconfig 来访问 Kubernetes API"
echo ""

