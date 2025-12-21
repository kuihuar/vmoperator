#!/bin/bash

# 修复 Multus 路径不匹配问题
# 问题：配置文件在主机上，但 Pod 内路径不一致

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复 Multus 路径不匹配问题"
echo_info "=========================================="
echo ""

# 1. 检查当前情况
echo_info "1. 诊断当前问题"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$MULTUS_POD" ]; then
    echo_error "  ✗ 未找到 Multus Pod"
    exit 1
fi

echo_info "  Pod: $MULTUS_POD"

# 检查主机路径
HOST_CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
HOST_CONFIG_FILE="$HOST_CNI_DIR/multus.d/daemon-config.json"

if [ -f "$HOST_CONFIG_FILE" ]; then
    echo_info "  ✓ 主机配置文件存在: $HOST_CONFIG_FILE"
else
    echo_error "  ✗ 主机配置文件不存在: $HOST_CONFIG_FILE"
    exit 1
fi

# 检查 DaemonSet 挂载配置
DS_MOUNT_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")
DS_HOST_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")

echo_info "  DaemonSet 挂载配置:"
echo_info "    主机路径: $DS_HOST_PATH"
echo_info "    Pod 内挂载点: $DS_MOUNT_PATH"

# 检查 Pod 内实际路径
echo ""
echo_info "2. 检查 Pod 内文件路径"
echo ""

# Multus 查找的路径通常是 /etc/cni/net.d/multus.d/daemon-config.json
POD_CONFIG_PATH="/etc/cni/net.d/multus.d/daemon-config.json"
POD_HOST_CONFIG_PATH="/host/etc/cni/net.d/multus.d/daemon-config.json"

echo_info "  检查 Pod 内路径:"
kubectl exec -n kube-system $MULTUS_POD -- test -f "$POD_CONFIG_PATH" 2>/dev/null && \
    echo_info "    ✓ $POD_CONFIG_PATH 存在" || \
    echo_warn "    ✗ $POD_CONFIG_PATH 不存在"

kubectl exec -n kube-system $MULTUS_POD -- test -f "$POD_HOST_CONFIG_PATH" 2>/dev/null && \
    echo_info "    ✓ $POD_HOST_CONFIG_PATH 存在" || \
    echo_warn "    ✗ $POD_HOST_CONFIG_PATH 不存在"

# 检查 Pod 内目录结构
echo ""
echo_info "  检查 Pod 内目录结构:"
if kubectl exec -n kube-system $MULTUS_POD -- test -d "/host/etc/cni/net.d" 2>/dev/null; then
    echo_info "    ✓ /host/etc/cni/net.d 目录存在"
    echo_info "    目录内容:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/ 2>&1 | head -10 || true
fi

if kubectl exec -n kube-system $MULTUS_POD -- test -d "/etc/cni/net.d" 2>/dev/null; then
    echo_info "    ✓ /etc/cni/net.d 目录存在"
    echo_info "    目录内容:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -la /etc/cni/net.d/ 2>&1 | head -10 || true
fi

# 2. 分析问题
echo ""
echo_info "3. 问题分析"
echo ""

if [ "$DS_MOUNT_PATH" = "/host/etc/cni/net.d" ]; then
    echo_warn "  问题: DaemonSet 挂载到 /host/etc/cni/net.d，但 Multus 查找 /etc/cni/net.d"
    echo_info "  解决方案: 需要将配置文件路径指向 /host/etc/cni/net.d，或者修改挂载点"
elif [ "$DS_MOUNT_PATH" = "/etc/cni/net.d" ]; then
    echo_warn "  问题: 虽然挂载到 /etc/cni/net.d，但 Pod 内仍无法访问"
    echo_info "  可能原因: 文件权限、子目录不存在等"
else
    echo_warn "  问题: 挂载路径异常: $DS_MOUNT_PATH"
fi

# 3. 解决方案
echo ""
echo_info "4. 实施修复"
echo ""

echo_warn "  方案 1: 修改 DaemonSet，将挂载点改为 /etc/cni/net.d（推荐）"
echo "  方案 2: 在 Pod 内创建符号链接（不可靠，重启会丢失）"
echo "  方案 3: 修改 daemon-config.json 中的路径配置"
echo ""

read -p "选择方案（1/2/3，默认1）: " SOLUTION
SOLUTION=${SOLUTION:-1}

case $SOLUTION in
    1)
        echo_info "  采用方案 1: 修改 DaemonSet 挂载点"
        
        # 备份
        kubectl get daemonset -n kube-system kube-multus-ds -o yaml > /tmp/multus-ds-backup-$(date +%Y%m%d-%H%M%S).yaml
        
        # 修改挂载点
        echo_info "  更新 DaemonSet..."
        kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/volumeMounts",
            "value": [
              {
                "name": "cni",
                "mountPath": "/etc/cni/net.d"
              },
              {
                "name": "cnibin",
                "mountPath": "/host/opt/cni/bin"
              }
            ]
          }
        ]' 2>&1
        
        if [ $? -eq 0 ]; then
            echo_info "  ✓ DaemonSet 已更新"
            
            # 重启 Pod
            echo_info "  重启 Pod..."
            kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
            sleep 10
            
            # 验证
            NEW_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$NEW_POD" ]; then
                if kubectl exec -n kube-system $NEW_POD -- test -f /etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null; then
                    echo_info "  ✓ 修复成功！Pod 内可以访问配置文件"
                else
                    echo_warn "  ⚠️  Pod 内仍无法访问，检查其他问题"
                fi
            fi
        else
            echo_error "  ✗ 更新失败"
        fi
        ;;
        
    2)
        echo_info "  采用方案 2: 创建符号链接（临时方案）"
        echo_warn "  ⚠️  这只是一个临时方案，Pod 重启后会丢失"
        
        if [ "$DS_MOUNT_PATH" = "/host/etc/cni/net.d" ]; then
            kubectl exec -n kube-system $MULTUS_POD -- sh -c "
                mkdir -p /etc/cni/net.d/multus.d
                ln -sf /host/etc/cni/net.d/multus.d/daemon-config.json /etc/cni/net.d/multus.d/daemon-config.json
                ls -la /etc/cni/net.d/multus.d/
            " 2>&1
            
            if kubectl exec -n kube-system $MULTUS_POD -- test -f /etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null; then
                echo_info "  ✓ 符号链接创建成功"
                echo_warn "  ⚠️  注意：Pod 重启后需要重新创建"
            else
                echo_error "  ✗ 符号链接创建失败"
            fi
        else
            echo_warn "  ⚠️  挂载路径不是 /host/etc/cni/net.d，无法创建符号链接"
        fi
        ;;
        
    3)
        echo_info "  采用方案 3: 修改 daemon-config.json 路径配置"
        echo_warn "  ⚠️  需要修改配置文件中的 confDir 路径"
        
        # 读取当前配置
        CURRENT_CONF_DIR=$(sudo cat "$HOST_CONFIG_FILE" | grep -o '"confDir":\s*"[^"]*"' | cut -d'"' -f4 || echo "/etc/cni/net.d")
        echo_info "  当前 confDir: $CURRENT_CONF_DIR"
        
        # 如果挂载到 /host/etc/cni/net.d，需要修改为 /host/etc/cni/net.d
        if [ "$DS_MOUNT_PATH" = "/host/etc/cni/net.d" ]; then
            echo_info "  更新配置文件..."
            sudo sed -i 's|"confDir":\s*"[^"]*"|"confDir": "/host/etc/cni/net.d"|' "$HOST_CONFIG_FILE"
            echo_info "  ✓ 配置文件已更新"
            
            # 重启 Pod
            kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
            sleep 10
        else
            echo_warn "  ⚠️  挂载路径不是 /host/etc/cni/net.d，跳过"
        fi
        ;;
        
    *)
        echo_error "  无效的选择"
        exit 1
        ;;
esac

# 5. 最终验证
echo ""
echo_info "5. 验证修复结果"
echo ""

sleep 5

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  检查 Pod 状态:"
    kubectl get pod -n kube-system $MULTUS_POD
    
    echo ""
    echo_info "  检查配置文件访问:"
    if kubectl exec -n kube-system $MULTUS_POD -- test -f /etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null; then
        echo_info "    ✓ Pod 内可以访问配置文件"
    else
        echo_warn "    ✗ Pod 内仍无法访问配置文件"
    fi
    
    echo ""
    echo_info "  查看 Pod 日志:"
    kubectl logs -n kube-system $MULTUS_POD --tail=20 2>&1 | head -15 || echo_warn "  无法获取日志"
    
    # 检查是否还有错误
    if kubectl logs -n kube-system $MULTUS_POD 2>&1 | grep -qi "panic\|error.*daemon-config\|no such file"; then
        echo_warn "    ⚠️  日志中仍有错误，可能需要进一步排查"
    else
        echo_info "    ✓ 日志中没有明显的错误"
    fi
else
    echo_warn "  等待 Pod 创建..."
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

