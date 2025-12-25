#!/bin/bash

# 获取 k3s 实际配置（通过 systemd 服务）

set -e

echo ""
echo "=========================================="
echo "k3s 实际配置检查"
echo "=========================================="
echo ""

# 1. 检查 systemd 服务配置（这里会显示实际启动参数）
echo "1. k3s systemd 服务配置（关键！）："
echo ""
sudo systemctl cat k3s 2>/dev/null | grep -A 5 "ExecStart" | sed 's/^/  /'

echo ""
echo "2. k3s 服务环境变量："
sudo systemctl cat k3s 2>/dev/null | grep "Environment" | sed 's/^/  /'

echo ""
echo "3. k3s 配置文件（如果存在）："
if [ -f /etc/rancher/k3s/config.yaml ]; then
    sudo cat /etc/rancher/k3s/config.yaml | sed 's/^/  /'
else
    echo "  配置文件不存在（使用默认配置）"
fi

echo ""
echo "4. 检查 k3s 进程树："
sudo pstree -p $(pgrep -f "k3s server" | head -1) 2>/dev/null || \
sudo pstree -p $(pgrep k3s | head -1) 2>/dev/null || \
echo "  无法获取进程树"

