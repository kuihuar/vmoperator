#!/bin/bash

# 检查所有可能的 Multus 配置文件位置

echo "检查所有可能的 Multus 配置位置..."
echo ""

echo "=== 1. k3s CNI 配置目录 ==="
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/ 2>/dev/null || echo "目录不存在"
echo ""

echo "=== 2. 主机 CNI 配置目录 ==="
sudo ls -la /etc/cni/net.d/ 2>/dev/null || echo "目录不存在"
echo ""

echo "=== 3. 查找所有 multus 相关文件 ==="
echo "在 k3s 目录:"
sudo find /var/lib/rancher/k3s -name "*multus*" -type f 2>/dev/null | head -10
echo ""

echo "在 /etc/cni:"
sudo find /etc/cni -name "*multus*" -type f 2>/dev/null | head -10
echo ""

echo "=== 4. 检查 CNI 配置文件内容 ==="
echo "k3s 目录中的配置文件:"
for conf in $(sudo ls -1 /var/lib/rancher/k3s/agent/etc/cni/net.d/*.{conf,conflist} 2>/dev/null | sort); do
    echo "文件: $conf"
    sudo cat "$conf" | jq -r '.type // .plugins[0].type // "unknown"' 2>/dev/null || echo "无法读取"
    echo ""
done

echo "主机 /etc/cni 目录中的配置文件:"
for conf in $(sudo ls -1 /etc/cni/net.d/*.{conf,conflist} 2>/dev/null | sort); do
    echo "文件: $conf"
    sudo cat "$conf" | jq -r '.type // .plugins[0].type // "unknown"' 2>/dev/null || echo "无法读取"
    echo ""
done

echo "=== 5. 检查 kubelet 实际使用的 CNI 配置 ==="
# kubelet 可能从不同位置读取配置
echo "检查 kubelet 配置..."
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf* 2>/dev/null | jq -r 'select(.type == "multus") | "找到 Multus 配置: \(.name)"' || echo "未找到 Multus 配置"
