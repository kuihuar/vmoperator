#!/bin/bash

# 配置 k3s 支持远程访问（从 macOS 访问）

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
echo_info "配置 k3s 支持远程访问"
echo_info "=========================================="
echo ""

# 获取虚拟机 IP
echo_info "1. 检测虚拟机 IP"
echo ""

# 尝试多种方法获取 IP
VM_IP=""
if command -v hostname &>/dev/null; then
    VM_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
fi

if [ -z "$VM_IP" ]; then
    VM_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null || echo "")
fi

if [ -z "$VM_IP" ]; then
    echo_warn "  无法自动检测 IP，请手动输入"
    read -p "虚拟机 IP 地址: " VM_IP
else
    echo_info "  检测到 IP: $VM_IP"
    read -p "确认使用此 IP？(y/n，默认y): " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        read -p "请输入正确的 IP 地址: " VM_IP
    fi
fi

if [ -z "$VM_IP" ]; then
    echo_error "  IP 地址不能为空"
    exit 1
fi

echo ""
echo_info "  将使用 IP: $VM_IP"
echo ""

# 选择配置方法
echo_info "2. 选择配置方法"
echo ""
echo "  1. 修改现有 k3s 配置（推荐，不需要重新安装）"
echo "  2. 重新安装 k3s（最可靠，但会删除现有数据）"
echo ""
read -p "选择方法 (1/2，默认1): " METHOD
METHOD=${METHOD:-1}

if [ "$METHOD" = "1" ]; then
    # 方法 1: 修改配置
    echo ""
    echo_info "3. 修改 k3s 配置"
    echo ""
    
    # 创建或更新配置文件
    echo_info "  创建 k3s 配置文件..."
    sudo mkdir -p /etc/rancher/k3s
    
    # 检查是否已有配置
    if [ -f /etc/rancher/k3s/config.yaml ]; then
        echo_warn "  配置文件已存在，备份..."
        sudo cp /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.backup.$(date +%Y%m%d-%H%M%S)
    fi
    
    # 添加 tls-san
    echo_info "  添加 tls-san 配置..."
    if grep -q "tls-san" /etc/rancher/k3s/config.yaml 2>/dev/null; then
        # 如果已有 tls-san，添加新的 IP
        sudo sed -i "/tls-san:/a\  - $VM_IP" /etc/rancher/k3s/config.yaml
    else
        # 如果没有，创建新配置
        sudo tee -a /etc/rancher/k3s/config.yaml > /dev/null <<EOF
tls-san:
  - $VM_IP
EOF
    fi
    
    echo_info "  ✓ 配置已更新"
    echo ""
    echo_info "  配置文件内容:"
    sudo cat /etc/rancher/k3s/config.yaml
    echo ""
    
    # 重启 k3s
    echo_warn "  4. 重启 k3s（这会导致短暂的集群中断）"
    read -p "确认重启？(y/n，默认y): " RESTART
    RESTART=${RESTART:-y}
    
    if [[ $RESTART =~ ^[Yy]$ ]]; then
        echo_info "  重启 k3s..."
        sudo systemctl restart k3s
        
        echo_info "  等待 k3s 启动（约 30 秒）..."
        sleep 30
        
        if sudo systemctl is-active --quiet k3s; then
            echo_info "  ✓ k3s 已启动"
        else
            echo_error "  ✗ k3s 启动失败"
            sudo systemctl status k3s --no-pager | head -10
            exit 1
        fi
    else
        echo_warn "  ⚠️  跳过重启，请稍后手动执行: sudo systemctl restart k3s"
    fi
    
else
    # 方法 2: 重新安装
    echo ""
    echo_warn "3. 重新安装 k3s（会删除现有数据）"
    echo ""
    echo_warn "  ⚠️  这将删除所有现有数据！"
    read -p "确认重新安装？(y/n，默认n): " REINSTALL
    REINSTALL=${REINSTALL:-n}
    
    if [[ ! $REINSTALL =~ ^[Yy]$ ]]; then
        echo_info "已取消"
        exit 0
    fi
    
    echo_info "  卸载 k3s..."
    sudo /usr/local/bin/k3s-uninstall.sh || true
    
    echo_info "  使用指定 IP 安装 k3s..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $VM_IP" sh -
    
    echo_info "  等待 k3s 启动..."
    sleep 30
fi

# 更新 kubeconfig
echo ""
echo_info "5. 更新 kubeconfig"
echo ""

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

# 修改 server 地址
sed -i "s|server: https://127.0.0.1:6443|server: https://$VM_IP:6443|g" ~/.kube/config

echo_info "  ✓ kubeconfig 已更新"
echo_info "  Server 地址: https://$VM_IP:6443"

# 验证
echo ""
echo_info "6. 验证配置"
echo ""

if kubectl get nodes &>/dev/null; then
    echo_info "  ✓ 连接成功"
    kubectl get nodes
else
    echo_error "  ✗ 连接失败"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "配置完成"
echo_info "=========================================="
echo ""
echo_info "在 macOS 上执行以下命令:"
echo ""
echo "  # 1. 复制 kubeconfig 到 macOS"
echo "  scp jianfen@$VM_IP:~/.kube/config ~/.kube/config-k3s"
echo ""
echo "  # 2. 使用 kubeconfig"
echo "  export KUBECONFIG=~/.kube/config-k3s"
echo ""
echo "  # 3. 测试连接"
echo "  kubectl get nodes"
echo ""

