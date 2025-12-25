#!/bin/bash

# 检查 k3s 进程和配置

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
echo_info "k3s 进程和配置检查"
echo_info "=========================================="
echo ""

# 1. 检查所有 k3s 相关进程
echo_info "1. 检查所有 k3s 相关进程..."
echo_info "  所有包含 k3s 的进程："
sudo ps aux | grep k3s | grep -v grep | head -20

# 2. 查找 k3s server 进程（可能名字不同）
echo ""
echo_info "2. 查找 k3s server 进程..."
K3S_SERVER=$(sudo ps aux | grep -E "k3s.*server|k3s server" | grep -v grep | head -1)
if [ -n "${K3S_SERVER}" ]; then
    echo_info "  找到 k3s server 进程："
    echo "${K3S_SERVER}" | sed 's/^/    /'
    
    # 提取完整命令行
    SERVER_PID=$(echo "${K3S_SERVER}" | awk '{print $2}')
    echo ""
    echo_info "  完整命令行（PID ${SERVER_PID}）："
    sudo cat /proc/${SERVER_PID}/cmdline | tr '\0' ' ' | sed 's/^/    /'
    echo ""
else
    echo_warn "  未找到 k3s server 进程"
    echo_info "  检查是否有其他形式的 k3s 主进程..."
    
    # 检查是否有 k3s 主进程（不一定是 server）
    K3S_MAIN=$(sudo ps aux | grep "/usr/local/bin/k3s" | grep -v "agent\|grep" | head -1)
    if [ -n "${K3S_MAIN}" ]; then
        echo_info "  找到可能的 k3s 主进程："
        echo "${K3S_MAIN}" | sed 's/^/    /'
        MAIN_PID=$(echo "${K3S_MAIN}" | awk '{print $2}')
        echo ""
        echo_info "  完整命令行（PID ${MAIN_PID}）："
        sudo cat /proc/${MAIN_PID}/cmdline 2>/dev/null | tr '\0' ' ' | sed 's/^/    /' || echo "    无法读取"
        echo ""
    fi
fi

# 3. 检查 systemd 服务
echo ""
echo_info "3. 检查 k3s systemd 服务..."
if systemctl is-active --quiet k3s 2>/dev/null; then
    echo_info "  ✓ k3s 服务运行中"
    echo_info "  服务状态："
    sudo systemctl status k3s --no-pager -l | head -15 | sed 's/^/    /'
    
    # 检查服务配置
    echo ""
    echo_info "  服务配置文件："
    sudo systemctl cat k3s 2>/dev/null | grep -E "ExecStart|Environment" | sed 's/^/    /' || echo "    无法读取"
else
    echo_warn "  k3s 服务未运行或无法检查"
fi

# 4. 检查 k3s 配置文件
echo ""
echo_info "4. 检查 k3s 配置文件..."
if [ -f /etc/rancher/k3s/config.yaml ]; then
    echo_info "  ✓ 找到配置文件: /etc/rancher/k3s/config.yaml"
    echo_info "  配置内容："
    sudo cat /etc/rancher/k3s/config.yaml | sed 's/^/    /' || echo "    无法读取"
else
    echo_info "  配置文件不存在（使用默认配置）"
fi

# 5. 检查环境变量
echo ""
echo_info "5. 检查 k3s 环境变量..."
if [ -f /etc/systemd/system/k3s.service ]; then
    echo_info "  systemd service 文件："
    sudo cat /etc/systemd/system/k3s.service | grep -E "Environment|ExecStart" | sed 's/^/    /'
fi

# 6. 检查 k3s 版本和节点信息
echo ""
echo_info "6. 检查 k3s 版本和节点信息..."
if command -v k3s &>/dev/null; then
    k3s --version | sed 's/^/    /'
    echo ""
    echo_info "  节点信息："
    kubectl get nodes -o wide 2>/dev/null | sed 's/^/    /' || echo "    无法获取"
fi

# 7. 总结
echo ""
echo_info "=========================================="
echo_info "检查总结"
echo_info "=========================================="
echo ""

if [ -z "${K3S_SERVER}" ] && [ -z "${K3S_MAIN}" ]; then
    echo_warn "⚠️  未找到 k3s server 主进程"
    echo_info "  可能的原因："
    echo "    1. k3s 以其他方式运行（如 agent 模式）"
    echo "    2. 进程名不同"
    echo "    3. 需要检查 systemd 服务配置"
fi

echo ""
echo_info "关键信息："
echo "  - 如果只有 k3s agent 进程，说明可能是 agent 节点"
echo "  - 如果是 server 节点，应该有 k3s server 进程"
echo "  - 需要查看完整的进程命令行来确定实际配置"

