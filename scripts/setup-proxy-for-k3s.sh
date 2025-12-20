#!/bin/bash

# 配置 k3s 使用代理

echo "=== 配置 k3s 使用代理 ==="

# 1. 获取代理信息
echo -e "\n请输入代理信息："
read -p "代理地址 (例如: http://proxy.example.com:8080): " PROXY_URL

if [ -z "$PROXY_URL" ]; then
    echo "错误: 代理地址不能为空"
    exit 1
fi

# 验证代理格式
if [[ ! $PROXY_URL =~ ^https?:// ]]; then
    echo "警告: 代理地址格式可能不正确，应该是 http:// 或 https:// 开头"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

read -p "NO_PROXY 列表 (可选，默认: localhost,127.0.0.1,0.0.0.0,10.0.0.0/8): " NO_PROXY_LIST
NO_PROXY_LIST=${NO_PROXY_LIST:-"localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,10.42.0.0/16,10.43.0.0/16"}

# 2. 创建代理配置
echo -e "\n2. 创建代理配置..."
sudo mkdir -p /etc/systemd/system/k3s.service.d/
sudo tee /etc/systemd/system/k3s.service.d/http-proxy.conf > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=$NO_PROXY_LIST"
EOF

echo "✓ 代理配置已创建: /etc/systemd/system/k3s.service.d/http-proxy.conf"
echo "  HTTP_PROXY=$PROXY_URL"
echo "  HTTPS_PROXY=$PROXY_URL"
echo "  NO_PROXY=$NO_PROXY_LIST"

# 3. 重新加载 systemd
echo -e "\n3. 重新加载 systemd..."
sudo systemctl daemon-reload
echo "✓ systemd 已重新加载"

# 4. 重启 k3s
echo -e "\n4. 重启 k3s..."
read -p "是否现在重启 k3s? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart k3s
    echo "等待 k3s 就绪..."
    sleep 15
    
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✓ k3s 已就绪"
    else
        echo "⚠️  k3s 可能还在启动中，请稍后检查: kubectl get nodes"
    fi
else
    echo "跳过重启，请稍后手动重启: sudo systemctl restart k3s"
fi

# 5. 测试代理
echo -e "\n5. 测试代理连接..."
if curl -s --proxy "$PROXY_URL" -I https://registry-1.docker.io > /dev/null 2>&1; then
    echo "✓ 代理连接正常"
else
    echo "⚠️  代理连接测试失败，请检查代理配置"
fi

echo -e "\n=== 完成 ==="
echo ""
echo "下一步："
echo "  1. 检查 Pod 状态: kubectl get pods -n kubevirt"
echo "  2. 如果 Pod 仍无法启动，删除并重新创建: kubectl delete pod -n kubevirt -l app=virt-operator"
echo "  3. 检查事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"

