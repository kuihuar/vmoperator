#!/bin/bash

# 配置 k3s 使用 Azure 中国镜像源

echo "=== 配置 k3s 使用 Azure 中国镜像源 ==="

# 1. 测试镜像源
echo -e "\n1. 测试 mirror.azure.cn..."
if curl -s -I --connect-timeout 5 https://mirror.azure.cn > /dev/null 2>&1; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://mirror.azure.cn 2>/dev/null)
    echo "✓ Azure 镜像源可访问 (HTTP $HTTP_CODE)"
else
    echo "⚠️  Azure 镜像源连接测试失败，但继续配置"
fi

# 2. 配置 k3s
echo -e "\n2. 配置 k3s 使用 Azure 镜像源..."
sudo mkdir -p /etc/rancher/k3s

# 备份现有配置
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.bak
    echo "✓ 已备份现有配置"
fi

# 创建新配置
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.azure.cn"
  registry-1.docker.io:
    endpoint:
      - "https://mirror.azure.cn"
EOF

echo "✓ 已配置 Azure 镜像源: /etc/rancher/k3s/registries.yaml"

# 3. 重启 k3s
echo -e "\n3. 重启 k3s（使配置生效）..."
read -p "是否现在重启 k3s? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart k3s
    echo "等待 k3s 就绪..."
    sleep 15
    
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✓ k3s 已就绪"
    else
        echo "⚠️  k3s 可能还在启动中"
    fi
else
    echo "跳过重启，请稍后手动重启: sudo systemctl restart k3s"
fi

# 4. 删除 Pod 重新创建
echo -e "\n4. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除"

echo -e "\n观察 Pod 状态:"
kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 成功启动，检查: kubectl get pods -n kubevirt -w"

