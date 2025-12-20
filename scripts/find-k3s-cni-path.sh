#!/bin/bash

# 查找 k3s CNI 配置路径

echo "=== 查找 k3s CNI 配置路径 ==="

# 可能的路径列表
POSSIBLE_PATHS=(
    "/var/lib/rancher/k3s/agent/etc/cni/net.d"
    "/var/lib/rancher/k3s/server/manifests"
    "/var/lib/rancher/k3s/agent/etc/cni"
    "/etc/cni/net.d"
    "/opt/cni/net.d"
)

echo -e "\n检查可能的路径:"
FOUND_PATH=""
for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo "✓ 找到: $path"
        if [ -z "$FOUND_PATH" ]; then
            FOUND_PATH="$path"
        fi
        echo "  内容:"
        sudo ls -la "$path" 2>/dev/null | head -5
        echo ""
    fi
done

# 检查 k3s 数据目录
echo "检查 k3s 数据目录:"
if [ -d /var/lib/rancher/k3s ]; then
    echo "✓ /var/lib/rancher/k3s 存在"
    echo "  子目录:"
    sudo ls -la /var/lib/rancher/k3s/ 2>/dev/null | head -10
    echo ""
    
    # 查找包含 cni 的目录
    echo "查找包含 'cni' 的目录:"
    sudo find /var/lib/rancher/k3s -type d -name "*cni*" 2>/dev/null | head -10
    echo ""
    
    # 查找 .conf 或 .conflist 文件
    echo "查找 CNI 配置文件:"
    sudo find /var/lib/rancher/k3s -name "*.conf" -o -name "*.conflist" 2>/dev/null | head -10
fi

# 检查 containerd 配置
echo -e "\n检查 containerd 配置（可能包含 CNI 路径）:"
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "containerd 配置中的 CNI 相关设置:"
    sudo grep -i "cni\|network" /var/lib/rancher/k3s/agent/etc/containerd/config.toml | head -10
fi

# 检查 k3s 进程
echo -e "\n检查 k3s 进程参数:"
sudo ps aux | grep k3s | grep -v grep | head -1

# 检查 k3s 服务配置
echo -e "\n检查 k3s 服务配置:"
if [ -f /etc/systemd/system/k3s.service ]; then
    echo "k3s.service 中的 ExecStart:"
    sudo grep "ExecStart" /etc/systemd/system/k3s.service
fi

# 检查 k3s 数据目录结构
echo -e "\n检查 k3s 数据目录结构:"
if [ -d /var/lib/rancher/k3s/data ]; then
    echo "k3s data 目录:"
    sudo ls -la /var/lib/rancher/k3s/data/ 2>/dev/null | head -10
    echo ""
    
    # 查找当前数据目录
    CURRENT_DATA=$(sudo ls -d /var/lib/rancher/k3s/data/*/ 2>/dev/null | head -1)
    if [ -n "$CURRENT_DATA" ]; then
        echo "当前数据目录: $CURRENT_DATA"
        echo "查找 CNI 相关:"
        sudo find "$CURRENT_DATA" -type d -name "*cni*" 2>/dev/null | head -5
    fi
fi

echo -e "\n=== 总结 ==="
if [ -n "$FOUND_PATH" ]; then
    echo "推荐使用的路径: $FOUND_PATH"
else
    echo "⚠️  未找到标准的 CNI 配置路径"
    echo "可能需要："
    echo "  1. 检查 k3s 是否使用不同的 CNI 配置方式"
    echo "  2. 检查 k3s 版本和安装方式"
    echo "  3. 查看 k3s 日志: sudo journalctl -u k3s -n 100"
fi

