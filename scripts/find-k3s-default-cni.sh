#!/bin/bash

# 查找 k3s 实际使用的默认 CNI 名称

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"

echo "查找 k3s 默认 CNI..."
echo ""

echo "1. 列出所有 CNI 配置文件:"
sudo ls -la "$CNI_CONF_DIR"/*.conf* 2>/dev/null || echo "未找到 .conf 文件"
echo ""

echo "2. 查找 .conf 文件:"
for conf in $(sudo ls -1 "$CNI_CONF_DIR"/*.conf 2>/dev/null | grep -v multus); do
    echo "  文件: $conf"
    echo "  内容:"
    sudo cat "$conf" | jq -r '.name // "未找到 name 字段"' 2>/dev/null || sudo cat "$conf" | head -5
    echo ""
done

echo "3. 查找 .conflist 文件:"
for conflist in $(sudo ls -1 "$CNI_CONF_DIR"/*.conflist 2>/dev/null); do
    echo "  文件: $conflist"
    echo "  内容:"
    sudo cat "$conflist" | jq -r '.plugins[0].name // .name // "未找到 name 字段"' 2>/dev/null || sudo cat "$conflist" | head -5
    echo ""
done

echo "4. 检查 k3s 实际使用的 CNI:"
# k3s 通常使用 flannel，但配置可能在 .conflist 文件中
if sudo ls -1 "$CNI_CONF_DIR"/*.conflist 2>/dev/null | grep -q .; then
    FIRST_CONFLIST=$(sudo ls -1 "$CNI_CONF_DIR"/*.conflist 2>/dev/null | head -1)
    CNI_NAME=$(sudo cat "$FIRST_CONFLIST" | jq -r '.plugins[0].name // .name // ""' 2>/dev/null || echo "")
    if [ -n "$CNI_NAME" ]; then
        echo "  找到 CNI 名称: $CNI_NAME"
        echo "  来自文件: $FIRST_CONFLIST"
    fi
fi

