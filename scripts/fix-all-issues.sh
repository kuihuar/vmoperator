#!/bin/bash

# 一键修复所有已知问题

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
echo_info "一键修复所有已知问题"
echo_info "=========================================="
echo ""

# 检查是否在目标机器上
if ! command -v kubectl &> /dev/null; then
    echo_error "kubectl 未找到，请确保在正确的环境中运行"
    exit 1
fi

# 1. 修复 k3s DNS 问题
echo ""
echo_info "=========================================="
echo_info "步骤 1: 修复 k3s DNS 问题"
echo_info "=========================================="
echo ""

if [ -f "/etc/systemd/system/k3s.service" ] || systemctl is-active --quiet k3s 2>/dev/null; then
    echo_info "检查 k3s DNS 配置..."
    
    if grep -q "K3S_RESOLV_CONF" /etc/systemd/system/k3s.service 2>/dev/null; then
        echo_info "  ✓ k3s DNS 配置已存在"
    else
        echo_warn "  ⚠️  需要修复 k3s DNS 配置"
        echo_info "  需要手动编辑 /etc/systemd/system/k3s.service"
        echo_info "  添加: Environment='K3S_RESOLV_CONF=/run/systemd/resolve/resolv.conf'"
        echo ""
        read -p "是否现在修复? (需要 sudo 权限) (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo sed -i '/\[Service\]/a Environment="K3S_RESOLV_CONF=/run/systemd/resolve/resolv.conf"' /etc/systemd/system/k3s.service
            echo_info "  ✓ 已更新 k3s.service"
            echo_info "  重启 k3s 服务..."
            sudo systemctl daemon-reload
            sudo systemctl restart k3s
            echo_info "  ✓ k3s 已重启"
            sleep 10
        fi
    fi
else
    echo_warn "  未检测到 k3s，跳过 DNS 修复"
fi

# 2. 修复 Multus CNI 路径问题
echo ""
echo_info "=========================================="
echo_info "步骤 2: 修复 Multus CNI 路径问题"
echo_info "=========================================="
echo ""

MULTUS_DS=$(kubectl get daemonset -n kube-system kube-multus-ds -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_DS" ]; then
    echo_info "检查 Multus DaemonSet 配置..."
    
    CURRENT_PATH=$(kubectl get $MULTUS_DS -n kube-system -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
    
    if [ "$CURRENT_PATH" = "/var/lib/rancher/k3s/agent/etc/cni/net.d" ]; then
        echo_info "  ✓ Multus 路径配置正确"
    else
        echo_warn "  ⚠️  Multus 路径配置需要修复"
        echo_info "  修复 Multus DaemonSet..."
        
        kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/volumeMounts",
            "value": [
              {
                "name": "cni",
                "mountPath": "/host/etc/cni/net.d"
              },
              {
                "name": "cnibin",
                "mountPath": "/host/opt/cni/bin"
              }
            ]
          },
          {
            "op": "replace",
            "path": "/spec/template/spec/volumes",
            "value": [
              {
                "name": "cni",
                "hostPath": {
                  "path": "/var/lib/rancher/k3s/agent/etc/cni/net.d",
                  "type": "Directory"
                }
              },
              {
                "name": "cnibin",
                "hostPath": {
                  "path": "/var/lib/rancher/k3s/data/current/bin",
                  "type": "Directory"
                }
              }
            ]
          }
        ]' 2>/dev/null || echo_warn "  修复失败，可能需要手动修复"
        
        echo_info "  删除旧的 Multus Pod..."
        kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
        echo_info "  ✓ Multus 已修复，等待 Pod 重启..."
        sleep 5
    fi
else
    echo_warn "  未找到 Multus DaemonSet，跳过"
fi

# 3. 检查 open-iscsi
echo ""
echo_info "=========================================="
echo_info "步骤 3: 检查 open-iscsi"
echo_info "=========================================="
echo ""

if command -v iscsiadm &> /dev/null; then
    echo_info "  ✓ open-iscsi 已安装"
    if systemctl is-active --quiet iscsid 2>/dev/null || sudo systemctl is-active --quiet iscsid 2>/dev/null; then
        echo_info "  ✓ iscsid 服务正在运行"
    else
        echo_warn "  ⚠️  iscsid 服务未运行"
        echo_info "  启动 iscsid 服务..."
        sudo systemctl enable iscsid 2>/dev/null || true
        sudo systemctl start iscsid 2>/dev/null || echo_warn "  启动失败，需要手动处理"
    fi
else
    echo_warn "  ⚠️  open-iscsi 未安装"
    echo_info "  需要手动安装: sudo apt-get install -y open-iscsi"
fi

# 4. 重启相关 Pod
echo ""
echo_info "=========================================="
echo_info "步骤 4: 重启相关 Pod"
echo_info "=========================================="
echo ""

echo_info "删除并重启 Pod..."
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
kubectl delete pod -n longhorn-system -l app=longhorn-manager --force --grace-period=0 2>/dev/null || true
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer --force --grace-period=0 2>/dev/null || true

echo_info "  ✓ Pod 已删除，等待自动重新创建..."
sleep 10

# 5. 检查状态
echo ""
echo_info "=========================================="
echo_info "步骤 5: 检查修复结果"
echo_info "=========================================="
echo ""

echo_info "Multus Pod 状态:"
kubectl get pods -n kube-system -l app=multus 2>/dev/null || echo_warn "  未找到"

echo ""
echo_info "Longhorn Manager Pod 状态:"
kubectl get pods -n longhorn-system -l app=longhorn-manager 2>/dev/null || echo_warn "  未找到"

echo ""
echo_info "Longhorn Driver Deployer Pod 状态:"
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer 2>/dev/null || echo_warn "  未找到"

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_warn "如果问题仍然存在，请运行诊断脚本:"
echo "  ./scripts/comprehensive-diagnosis.sh"
echo ""
echo_info "等待 1-2 分钟后再次检查 Pod 状态:"
echo "  kubectl get pods -n kube-system -l app=multus"
echo "  kubectl get pods -n longhorn-system"

