#!/bin/bash

# 完整诊断并修复 Multus 所有问题

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
echo_info "完整诊断并修复 Multus"
echo_info "=========================================="
echo ""

# 1. 获取最新错误
echo_info "1. 当前错误"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod: $MULTUS_POD"
    echo_info "  最新错误:"
    kubectl logs -n kube-system $MULTUS_POD -c kube-multus --tail=5 2>&1 | head -3
    echo ""
fi

# 2. 检查 DaemonSet 配置
echo_info "2. DaemonSet 配置"
echo ""

DS_NAME="kube-multus-ds"
CNI_MOUNT=$(kubectl get daemonset -n kube-system $DS_NAME -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")
CNI_HOST=$(kubectl get daemonset -n kube-system $DS_NAME -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")

echo_info "  挂载: $CNI_HOST -> $CNI_MOUNT"
echo ""

# 3. 检查所有配置文件
echo_info "3. 检查配置文件"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
DAEMON_CONFIG="$CNI_CONF_DIR/multus.d/daemon-config.json"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

echo_info "  检查 daemon-config.json..."
if [ -f "$DAEMON_CONFIG" ]; then
    echo_info "  ✓ 文件存在"
    CONF_DIR=$(sudo cat "$DAEMON_CONFIG" | jq -r '.confDir // ""' 2>/dev/null || echo "")
    echo_info "    confDir: $CONF_DIR"
    
    # 检查路径是否正确（应该是 Pod 内路径，不是主机路径）
    if [[ "$CONF_DIR" == /var/lib/rancher/k3s* ]]; then
        echo_error "    ✗ 路径错误：使用了主机路径，应该是 Pod 内路径"
        NEED_FIX=true
    elif [[ "$CONF_DIR" == /host/etc/cni/net.d ]]; then
        echo_info "    ✓ 路径正确"
        NEED_FIX=false
    else
        echo_warn "    ⚠️  路径可能是: $CONF_DIR"
        NEED_FIX=true
    fi
else
    echo_error "  ✗ 文件不存在"
    NEED_FIX=true
fi

# 4. 修复配置
echo ""
if [ "$NEED_FIX" = true ]; then
    echo_info "4. 修复配置"
    echo ""
    
    sudo mkdir -p "$CNI_CONF_DIR/multus.d"
    
    # 根据 DaemonSet 挂载确定正确的 Pod 内路径
    if [ -n "$CNI_MOUNT" ]; then
        CONF_DIR_POD="$CNI_MOUNT"
    else
        CONF_DIR_POD="/host/etc/cni/net.d"
    fi
    
    echo_info "  使用 Pod 内路径: $CONF_DIR_POD"
    
    sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "$CONF_DIR_POD",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log",
  "kubeconfig": "$CONF_DIR_POD/multus.d/multus.kubeconfig"
}
EOF
    
    sudo chmod 644 "$DAEMON_CONFIG"
    echo_info "  ✓ 已修复"
    
    echo ""
    echo_info "  新配置:"
    sudo cat "$DAEMON_CONFIG" | jq '.'
else
    echo_info "4. 配置正确，无需修复"
fi

# 5. 验证文件存在
echo ""
echo_info "5. 验证文件存在"
echo ""

HOST_KUBECONFIG="$CNI_CONF_DIR/multus.d/multus.kubeconfig"
if [ -f "$HOST_KUBECONFIG" ]; then
    echo_info "  ✓ kubeconfig 存在: $HOST_KUBECONFIG"
else
    echo_error "  ✗ kubeconfig 不存在，创建..."
    sudo ./scripts/create-kubeconfig-official.sh
fi

# 6. 重启 Pod
echo ""
echo_info "6. 重启 Pod"
echo ""

kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo_info "  ✓ Pod 已删除"
echo_info "  等待 10 秒..."
sleep 10

# 7. 检查结果
echo ""
echo_info "7. 检查结果"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  新 Pod: $MULTUS_POD"
    kubectl get pod -n kube-system $MULTUS_POD
    
    echo ""
    sleep 5
    echo_info "  最新日志:"
    kubectl logs -n kube-system $MULTUS_POD -c kube-multus --tail=10 2>&1 || echo_warn "  无法获取日志"
    
    STATUS=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$STATUS" = "Running" ]; then
        echo ""
        echo_info "  ✓ Pod 运行中！"
    else
        echo ""
        echo_warn "  ⚠️  Pod 状态: $STATUS"
    fi
else
    echo_warn "  ⚠️  Pod 尚未创建"
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""

