#!/bin/bash

# 诊断并修复 Multus kubeconfig 问题

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
echo_info "诊断并修复 Multus kubeconfig 问题"
echo_info "=========================================="
echo ""

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
KUBECONFIG_FILE="$CNI_DIR/multus.d/multus.kubeconfig"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

# 1. 检查主机上的文件
echo_info "1. 检查主机上的文件"
echo ""

if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  ✓ 文件存在: $KUBECONFIG_FILE"
    sudo ls -la "$KUBECONFIG_FILE"
else
    echo_error "  ✗ 文件不存在: $KUBECONFIG_FILE"
    echo_info "  创建文件..."
    
    sudo mkdir -p "$CNI_DIR/multus.d"
    if [ -f "$K3S_KUBECONFIG" ]; then
        sudo cp "$K3S_KUBECONFIG" "$KUBECONFIG_FILE"
        sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$KUBECONFIG_FILE"
        sudo chmod 644 "$KUBECONFIG_FILE"
        echo_info "  ✓ 文件已创建"
    else
        echo_error "  ✗ 无法创建：未找到 k3s kubeconfig"
        exit 1
    fi
fi

# 2. 检查 Multus DaemonSet 挂载配置
echo ""
echo_info "2. 检查 Multus DaemonSet 挂载配置"
echo ""

MULTUS_DS=$(kubectl get daemonset -n kube-system kube-multus-ds -o name 2>/dev/null || echo "")
if [ -z "$MULTUS_DS" ]; then
    echo_error "  ✗ 未找到 Multus DaemonSet"
    exit 1
fi

DS_HOST_PATH=$(kubectl get $MULTUS_DS -n kube-system -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get $MULTUS_DS -n kube-system -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

echo_info "  DaemonSet 挂载配置:"
echo_info "    主机路径: $DS_HOST_PATH"
echo_info "    Pod 内挂载点: $DS_MOUNT_PATH"

if [ "$DS_HOST_PATH" != "$CNI_DIR" ]; then
    echo_warn "  ⚠️  挂载路径不匹配！"
    echo_warn "    期望: $CNI_DIR"
    echo_warn "    实际: $DS_HOST_PATH"
    echo_info "  需要修复 DaemonSet 挂载路径"
    NEED_FIX=true
else
    echo_info "  ✓ 挂载路径正确"
    NEED_FIX=false
fi

# 3. 检查 Pod 内文件访问
echo ""
echo_info "3. 检查 Pod 内文件访问"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Multus Pod: $MULTUS_POD"
    
    # 根据挂载点检查
    if [ "$DS_MOUNT_PATH" = "/etc/cni/net.d" ]; then
        POD_PATH="/etc/cni/net.d/multus.d/multus.kubeconfig"
    elif [ "$DS_MOUNT_PATH" = "/host/etc/cni/net.d" ]; then
        POD_PATH="/host/etc/cni/net.d/multus.d/multus.kubeconfig"
    else
        POD_PATH="/etc/cni/net.d/multus.d/multus.kubeconfig"  # 默认
    fi
    
    echo_info "  检查 Pod 内路径: $POD_PATH"
    
    if kubectl exec -n kube-system $MULTUS_POD -- test -f "$POD_PATH" 2>/dev/null; then
        echo_info "  ✓ Pod 内可以访问文件"
    else
        echo_error "  ✗ Pod 内无法访问文件"
        echo_info "  尝试其他路径..."
        
        # 尝试多个可能的路径
        for path in "/etc/cni/net.d/multus.d/multus.kubeconfig" "/host/etc/cni/net.d/multus.d/multus.kubeconfig"; do
            if kubectl exec -n kube-system $MULTUS_POD -- test -f "$path" 2>/dev/null; then
                echo_info "  ✓ 找到文件在: $path"
                break
            fi
        done
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

# 4. 修复（如果需要）
echo ""
if [ "$NEED_FIX" = true ] || [ ! -f "$KUBECONFIG_FILE" ]; then
    echo_info "4. 执行修复"
    echo ""
    
    # 确保文件存在
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        echo_info "  创建 kubeconfig 文件..."
        sudo mkdir -p "$CNI_DIR/multus.d"
        sudo cp "$K3S_KUBECONFIG" "$KUBECONFIG_FILE"
        sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$KUBECONFIG_FILE"
        sudo chmod 644 "$KUBECONFIG_FILE"
        echo_info "  ✓ 文件已创建"
    fi
    
    # 如果需要修复 DaemonSet
    if [ "$NEED_FIX" = true ]; then
        echo_info "  修复 DaemonSet 挂载路径..."
        
        # 备份
        kubectl get $MULTUS_DS -n kube-system -o yaml > /tmp/multus-ds-backup-$(date +%Y%m%d-%H%M%S).yaml
        
        # 使用 patch 修复
        kubectl patch $MULTUS_DS -n kube-system --type json -p "[
          {
            \"op\": \"replace\",
            \"path\": \"/spec/template/spec/volumes\",
            \"value\": [
              {
                \"name\": \"cni\",
                \"hostPath\": {
                  \"path\": \"$CNI_DIR\",
                  \"type\": \"Directory\"
                }
              },
              {
                \"name\": \"cnibin\",
                \"hostPath\": {
                  \"path\": \"/var/lib/rancher/k3s/data/cni\",
                  \"type\": \"Directory\"
                }
              }
            ]
          },
          {
            \"op\": \"replace\",
            \"path\": \"/spec/template/spec/containers/0/volumeMounts\",
            \"value\": [
              {
                \"name\": \"cni\",
                \"mountPath\": \"/etc/cni/net.d\"
              },
              {
                \"name\": \"cnibin\",
                \"mountPath\": \"/host/opt/cni/bin\"
              }
            ]
          }
        ]" 2>&1
        
        echo_info "  ✓ DaemonSet 已修复"
        
        # 重启 Pod
        echo_info "  重启 Multus Pod..."
        kubectl delete pod -n kube-system $MULTUS_POD --force --grace-period=0 2>/dev/null || true
        sleep 5
    fi
else
    echo_info "4. 不需要修复"
fi

# 5. 最终验证
echo ""
echo_info "5. 最终验证"
echo ""

if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  ✓ 主机文件存在"
    sudo ls -lh "$KUBECONFIG_FILE"
else
    echo_error "  ✗ 主机文件不存在"
fi

sleep 5

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    if kubectl exec -n kube-system $MULTUS_POD -- test -f /etc/cni/net.d/multus.d/multus.kubeconfig 2>/dev/null; then
        echo_info "  ✓ Pod 内文件可访问"
    else
        echo_warn "  ⚠️  Pod 内文件仍无法访问"
        echo_info "  检查 Pod 日志:"
        kubectl logs -n kube-system $MULTUS_POD --tail=10 2>&1 | head -5
    fi
fi

echo ""
echo_info "=========================================="
echo_info "诊断完成"
echo_info "=========================================="
echo ""
echo_info "如果问题仍然存在，请检查："
echo "  1. Multus DaemonSet 配置: kubectl get daemonset -n kube-system kube-multus-ds -o yaml"
echo "  2. 文件权限: sudo ls -la $KUBECONFIG_FILE"
echo "  3. 重启所有受影响的 Pod"
echo ""

