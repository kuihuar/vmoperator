#!/bin/bash

# 检查 daemon-config.json

DAEMON_CONFIG="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json"

echo "检查 daemon-config.json:"
echo ""

if [ -f "$DAEMON_CONFIG" ]; then
    echo "文件内容:"
    sudo cat "$DAEMON_CONFIG" | jq '.'
    echo ""
    
    KUBECONFIG=$(sudo cat "$DAEMON_CONFIG" | jq -r '.kubeconfig // ""')
    if [ -n "$KUBECONFIG" ]; then
        echo "kubeconfig 路径: $KUBECONFIG"
        echo ""
        
        if [ -f "$KUBECONFIG" ]; then
            echo "✓ 文件存在"
        else
            echo "✗ 文件不存在"
        fi
    else
        echo "未配置 kubeconfig"
    fi
else
    echo "文件不存在"
fi

