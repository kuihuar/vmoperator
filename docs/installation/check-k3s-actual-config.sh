#!/bin/bash

# 检查 k3s 实际启动参数（完整版）

echo "=========================================="
echo "k3s 实际启动参数检查"
echo "=========================================="
echo ""

echo "1. systemd 服务完整配置："
sudo systemctl cat k3s | grep -A 20 "ExecStart" | head -30

echo ""
echo "2. k3s 进程实际命令行："
sudo ps aux | grep "k3s server" | grep -v grep | head -1
if [ $? -eq 0 ]; then
    K3S_PID=$(sudo ps aux | grep "k3s server" | grep -v grep | awk '{print $2}' | head -1)
    echo "   进程 PID: ${K3S_PID}"
    echo "   完整命令行："
    sudo cat /proc/${K3S_PID}/cmdline 2>/dev/null | tr '\0' ' ' | sed 's/^/    /' || echo "    无法读取"
fi

echo ""
echo "3. 检查是否禁用 ServiceLB："
if sudo systemctl cat k3s 2>/dev/null | grep -qE "disable.*servicelb|--disable servicelb"; then
    echo "   ✓ 已禁用 ServiceLB"
elif sudo ps aux | grep "k3s server" | grep -v grep | grep -qE "disable.*servicelb|--disable servicelb"; then
    echo "   ✓ 已禁用 ServiceLB（在进程命令行中）"
else
    echo "   ✗ 未禁用 ServiceLB"
    echo "   需要添加 --disable servicelb 参数"
fi

echo ""
echo "4. 检查网络配置："
if sudo ps aux | grep "k3s server" | grep -v grep | grep -qE "cluster-cidr|service-cidr"; then
    echo "   ✓ 已明确指定网络配置"
    sudo ps aux | grep "k3s server" | grep -v grep | grep -oE "(cluster-cidr|service-cidr) [^ ]+" | sed 's/^/    /'
else
    echo "   ⚠️  使用默认网络配置"
fi

