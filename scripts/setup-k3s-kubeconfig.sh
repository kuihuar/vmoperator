#!/bin/bash

# 配置 k3s kubeconfig 脚本

echo "=== 配置 k3s kubeconfig ==="

# 检查 k3s 是否安装
if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "错误: k3s 未安装或 k3s.yaml 不存在"
    echo "请先安装 k3s: curl -sfL https://get.k3s.io | sh -"
    exit 1
fi

# 方法 1: 复制到 ~/.kube/config
echo "方法 1: 复制 k3s.yaml 到 ~/.kube/config"
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# 检查 server 地址
SERVER=$(grep server ~/.kube/config | awk '{print $2}')
echo "当前 server 地址: $SERVER"

# 如果 server 是 localhost 或 127.0.0.1，提示可能需要修改
if [[ "$SERVER" == *"localhost"* ]] || [[ "$SERVER" == *"127.0.0.1"* ]]; then
    echo ""
    echo "⚠️  注意: server 地址是 $SERVER"
    echo "如果从远程访问或使用不同的网络接口，可能需要修改为实际的 IP 地址"
    echo ""
    echo "获取本机 IP 地址:"
    hostname -I | awk '{print $1}'
    echo ""
    echo "如果需要修改，运行:"
    echo "  sed -i 's|server:.*|server: https://<your-ip>:6443|' ~/.kube/config"
fi

# 验证连接
echo ""
echo "=== 验证集群连接 ==="
if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ 集群连接成功"
    kubectl get nodes
else
    echo "✗ 集群连接失败"
    echo "请检查:"
    echo "  1. k3s 服务是否运行: sudo systemctl status k3s"
    echo "  2. server 地址是否正确"
    echo "  3. 防火墙是否允许 6443 端口"
    exit 1
fi

echo ""
echo "=== 设置环境变量（可选）==="
echo "如果需要在当前 shell 中使用，运行:"
echo "  export KUBECONFIG=~/.kube/config"
echo ""
echo "或者添加到 ~/.bashrc 或 ~/.zshrc:"
echo "  echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc"

