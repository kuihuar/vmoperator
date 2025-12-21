#!/bin/bash

# 修复 k3s DNS 配置以支持 Longhorn
# 参考: https://longhorn.io/kb/troubleshooting-dns-resolution-failed/

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_info "开始修复 k3s DNS 配置以支持 Longhorn"

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then 
    echo_error "请使用 sudo 运行此脚本"
    exit 1
fi

# 1. 检查当前 resolv.conf
echo_info "步骤 1: 检查当前 /etc/resolv.conf 配置"
if [ -L /etc/resolv.conf ]; then
    REAL_PATH=$(readlink -f /etc/resolv.conf)
    echo_info "发现 /etc/resolv.conf 是符号链接，指向: $REAL_PATH"
    
    if [[ "$REAL_PATH" == *"systemd/resolve/stub-resolv.conf"* ]]; then
        echo_warn "检测到 systemd-resolved stub 配置"
        REAL_RESOLV_CONF="/run/systemd/resolve/resolv.conf"
        if [ -f "$REAL_RESOLV_CONF" ]; then
            echo_info "找到真实的 resolv.conf: $REAL_RESOLV_CONF"
            RESOLV_CONF_PATH="$REAL_RESOLV_CONF"
        else
            echo_warn "未找到 $REAL_RESOLV_CONF，使用 /etc/resolv.conf"
            RESOLV_CONF_PATH="/etc/resolv.conf"
        fi
    else
        RESOLV_CONF_PATH="$REAL_PATH"
    fi
else
    RESOLV_CONF_PATH="/etc/resolv.conf"
fi

echo_info "将使用 resolv.conf 路径: $RESOLV_CONF_PATH"

# 2. 确定 k3s 服务文件位置
echo_info "步骤 2: 查找 k3s 服务文件"
if [ -f /etc/systemd/system/k3s.service ]; then
    K3S_SERVICE="/etc/systemd/system/k3s.service"
elif [ -f /usr/local/lib/systemd/system/k3s.service ]; then
    K3S_SERVICE="/usr/local/lib/systemd/system/k3s.service"
else
    echo_error "未找到 k3s.service 文件"
    exit 1
fi

echo_info "找到 k3s 服务文件: $K3S_SERVICE"

# 3. 备份服务文件
echo_info "步骤 3: 备份 k3s 服务文件"
cp "$K3S_SERVICE" "${K3S_SERVICE}.backup.$(date +%Y%m%d_%H%M%S)"
echo_info "已备份到: ${K3S_SERVICE}.backup.$(date +%Y%m%d_%H%M%S)"

# 4. 检查是否已配置 K3S_RESOLV_CONF
if grep -q "K3S_RESOLV_CONF" "$K3S_SERVICE"; then
    echo_warn "检测到 K3S_RESOLV_CONF 已存在，将更新为: $RESOLV_CONF_PATH"
    # 更新现有配置
    sed -i "s|K3S_RESOLV_CONF=.*|K3S_RESOLV_CONF=$RESOLV_CONF_PATH|g" "$K3S_SERVICE"
else
    echo_info "步骤 4: 添加 K3S_RESOLV_CONF 环境变量"
    # 在 ExecStart 之前添加环境变量
    if grep -q "\[Service\]" "$K3S_SERVICE"; then
        # 在 [Service] 部分添加环境变量
        sed -i "/\[Service\]/a Environment=\"K3S_RESOLV_CONF=$RESOLV_CONF_PATH\"" "$K3S_SERVICE"
    else
        echo_error "未找到 [Service] 部分"
        exit 1
    fi
fi

# 5. 显示修改后的配置
echo_info "步骤 5: 显示修改后的配置"
echo "---"
grep -A 5 "\[Service\]" "$K3S_SERVICE" | head -10
echo "---"

# 6. 重新加载 systemd 并重启 k3s
echo_info "步骤 6: 重新加载 systemd 配置"
systemctl daemon-reload

echo_warn "步骤 7: 重启 k3s 服务"
echo_warn "这将重启 k3s，可能导致短暂的连接中断"
read -p "是否继续? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart k3s
    echo_info "等待 k3s 启动..."
    sleep 5
    
    # 检查 k3s 状态
    if systemctl is-active --quiet k3s; then
        echo_info "✓ k3s 服务已成功重启"
    else
        echo_error "✗ k3s 服务启动失败"
        systemctl status k3s
        exit 1
    fi
else
    echo_warn "未重启 k3s，请手动执行: sudo systemctl restart k3s"
fi

# 7. 验证配置
echo_info "步骤 8: 验证 DNS 配置"
if kubectl cluster-info &> /dev/null; then
    echo_info "✓ Kubernetes 集群连接正常"
    
    # 检查 CoreDNS
    echo_info "检查 CoreDNS Pods..."
    kubectl get pods -n kube-system | grep coredns || kubectl get pods -n kube-system | grep coredns
    
    # 检查 longhorn-backend Service
    if kubectl get namespace longhorn-system &> /dev/null; then
        echo_info "检查 longhorn-backend Service..."
        kubectl get svc -n longhorn-system longhorn-backend 2>/dev/null || echo_warn "longhorn-backend Service 不存在（Longhorn 可能尚未安装）"
    fi
else
    echo_warn "无法连接到 Kubernetes 集群，请检查 k3s 状态"
fi

echo ""
echo_info "修复完成！"
echo_info "如果 longhorn-manager 仍在重启，请："
echo "  1. 检查 longhorn-manager Pod 日志: kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
echo "  2. 测试 DNS 解析: kubectl exec -it <longhorn-manager-pod> -- nslookup longhorn-backend.longhorn-system.svc"
echo "  3. 查看事件: kubectl get events -n longhorn-system --sort-by='.lastTimestamp'"

