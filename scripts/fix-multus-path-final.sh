#!/bin/bash

# 最终修复 Multus 路径问题 - 基于完整分析

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
echo_info "最终修复 Multus 路径问题"
echo_info "=========================================="
echo ""

# 1. 检查 DaemonSet 实际挂载配置
echo_info "1. 检查 DaemonSet 挂载配置"
echo ""

DS_NAME="kube-multus-ds"

# 检查 DaemonSet 是否存在
if ! kubectl get daemonset -n kube-system $DS_NAME &>/dev/null; then
    echo_error "  ✗ DaemonSet 不存在: $DS_NAME"
    echo_info "  请先安装 Multus"
    exit 1
fi

# 获取挂载配置（尝试多个可能的 volume 名称）
CNI_MOUNT=""
CNI_HOST=""

# 尝试常见的 volume 名称
for VOL_NAME in "cni" "cni-conf-dir" "cniconfig"; do
    CNI_MOUNT=$(kubectl get daemonset -n kube-system $DS_NAME -o jsonpath="{.spec.template.spec.containers[0].volumeMounts[?(@.name==\"$VOL_NAME\")].mountPath}" 2>/dev/null || echo "")
    CNI_HOST=$(kubectl get daemonset -n kube-system $DS_NAME -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$VOL_NAME\")].hostPath.path}" 2>/dev/null || echo "")
    if [ -n "$CNI_MOUNT" ] && [ -n "$CNI_HOST" ]; then
        break
    fi
done

# 如果还是找不到，尝试列出所有 volumes
if [ -z "$CNI_MOUNT" ] || [ -z "$CNI_HOST" ]; then
    echo_warn "  ⚠️  无法通过常见名称找到挂载，尝试列出所有 volumes..."
    kubectl get daemonset -n kube-system $DS_NAME -o jsonpath='{.spec.template.spec.volumes[*].name}' | tr ' ' '\n' | while read vol_name; do
        if [ -n "$vol_name" ]; then
            vol_path=$(kubectl get daemonset -n kube-system $DS_NAME -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$vol_name\")].hostPath.path}" 2>/dev/null || echo "")
            if echo "$vol_path" | grep -q "cni\|net.d"; then
                CNI_HOST="$vol_path"
                CNI_MOUNT=$(kubectl get daemonset -n kube-system $DS_NAME -o jsonpath="{.spec.template.spec.containers[0].volumeMounts[?(@.name==\"$vol_name\")].mountPath}" 2>/dev/null || echo "")
                break
            fi
        fi
    done
fi

if [ -z "$CNI_MOUNT" ] || [ -z "$CNI_HOST" ]; then
    echo_error "  ✗ 无法获取 DaemonSet 挂载配置"
    echo_info "  DaemonSet 配置："
    kubectl get daemonset -n kube-system $DS_NAME -o yaml | grep -A 10 "volumes:" | head -20
    exit 1
fi

echo_info "  主机路径: $CNI_HOST"
echo_info "  Pod 内挂载点: $CNI_MOUNT"
echo ""

# 2. 创建正确的 daemon-config.json
echo_info "2. 创建正确的 daemon-config.json"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
DAEMON_CONFIG="$CNI_CONF_DIR/multus.d/daemon-config.json"

sudo mkdir -p "$CNI_CONF_DIR/multus.d"

# 使用 Pod 内路径（挂载后的路径）
CONF_DIR_POD="$CNI_MOUNT"
KUBECONFIG_POD="$CNI_MOUNT/multus.d/multus.kubeconfig"

echo_info "  配置:"
echo_info "    confDir (Pod 内): $CONF_DIR_POD"
echo_info "    kubeconfig (Pod 内): $KUBECONFIG_POD"
echo ""

# 备份现有配置
if [ -f "$DAEMON_CONFIG" ]; then
    sudo cp "$DAEMON_CONFIG" "$DAEMON_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"
fi

# 创建正确配置
sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "$CONF_DIR_POD",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log",
  "kubeconfig": "$KUBECONFIG_POD"
}
EOF

sudo chmod 644 "$DAEMON_CONFIG"

echo_info "  ✓ 已创建: $DAEMON_CONFIG"
echo ""
echo_info "  内容:"
sudo cat "$DAEMON_CONFIG" | jq '.'
echo ""

# 3. 验证主机文件存在
echo_info "3. 验证主机文件存在"
echo ""

HOST_KUBECONFIG="$CNI_CONF_DIR/multus.d/multus.kubeconfig"
if [ -f "$HOST_KUBECONFIG" ]; then
    echo_info "  ✓ kubeconfig 存在: $HOST_KUBECONFIG"
else
    echo_error "  ✗ kubeconfig 不存在，创建..."
    sudo ./scripts/create-kubeconfig-official.sh
fi

# 4. 重启 Pod
echo ""
echo_info "4. 重启 Pod 应用新配置"
echo ""

kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo_info "  ✓ Pod 已删除"
echo_info "  等待 10 秒..."
sleep 10

# 5. 检查结果
echo ""
echo_info "5. 检查结果"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  新 Pod: $MULTUS_POD"
    kubectl get pod -n kube-system $MULTUS_POD
    
    echo ""
    sleep 5
    echo_info "  最新日志:"
    kubectl logs -n kube-system $MULTUS_POD -c kube-multus --tail=10 2>&1 || echo_warn "  无法获取日志"
    
    # 检查是否还有路径错误
    if kubectl logs -n kube-system $MULTUS_POD -c kube-multus 2>&1 | grep -q "cni-conf-dir is not found"; then
        echo_error "  ✗ 仍有路径错误"
        echo_info "  检查 Pod 内路径访问..."
        
        # 尝试在 Pod 内检查
        if kubectl exec -n kube-system $MULTUS_POD -- test -d "$CONF_DIR_POD" 2>/dev/null; then
            echo_info "  ✓ Pod 内可以访问目录: $CONF_DIR_POD"
        else
            echo_error "  ✗ Pod 内无法访问目录: $CONF_DIR_POD"
            echo_info "  可能挂载配置有问题"
        fi
    else
        STATUS=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$STATUS" = "Running" ]; then
            echo ""
            echo_info "  ✓ Pod 运行中！问题已解决！"
        fi
    fi
else
    echo_warn "  ⚠️  Pod 尚未创建"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

