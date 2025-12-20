#!/bin/bash

# 配置 k3s 使用阿里云镜像源

echo "=== 配置 k3s 使用阿里云镜像源 ==="

# 1. 测试镜像源
echo -e "\n1. 测试阿里云镜像源..."
ALIYUN_MIRROR="https://e0hhb5lk.mirror.aliyuncs.com"

if curl -s -I --connect-timeout 5 "$ALIYUN_MIRROR" > /dev/null 2>&1; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ALIYUN_MIRROR" 2>/dev/null)
    echo "✓ 阿里云镜像源可访问 (HTTP $HTTP_CODE)"
else
    echo "⚠️  阿里云镜像源连接测试失败，但继续配置"
fi

# 2. 配置 k3s
echo -e "\n2. 配置 k3s 使用阿里云镜像源..."
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
      - "$ALIYUN_MIRROR"
  registry-1.docker.io:
    endpoint:
      - "$ALIYUN_MIRROR"
EOF

echo "✓ 已配置阿里云镜像源: /etc/rancher/k3s/registries.yaml"
echo "  镜像源地址: $ALIYUN_MIRROR"

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

# 4. 确保本地镜像已 tag
echo -e "\n4. 确保本地 pause 镜像已 tag..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if ! crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "Tag 本地 pause 镜像..."
    sudo ctr -n k8s.io images tag \
        registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
        rancher/mirrored-pause:3.6 2>&1 | head -3
    echo "✓ Tag 完成"
else
    echo "✓ 本地已有 rancher/mirrored-pause:3.6 镜像"
fi

# 5. 测试从阿里云镜像源拉取
echo -e "\n5. 测试从阿里云镜像源拉取 pause 镜像..."
echo "尝试拉取 rancher/mirrored-pause:3.6..."
PULL_OUTPUT=$(crictl pull rancher/mirrored-pause:3.6 2>&1)
PULL_EXIT=$?

if [ $PULL_EXIT -eq 0 ]; then
    echo "✓ 成功从阿里云镜像源拉取镜像"
elif echo "$PULL_OUTPUT" | grep -q "already exists\|Image.*already present"; then
    echo "✓ 镜像已存在（本地或已拉取）"
else
    echo "⚠️  拉取失败，输出:"
    echo "$PULL_OUTPUT" | head -3
    echo ""
    echo "但本地已有镜像，k3s 应该可以使用本地镜像"
fi

# 6. 删除 Pod 重新创建
echo -e "\n6. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除"

echo -e "\n观察 Pod 状态:"
kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 成功启动，下一步："
echo "  1. 等待 Operator 就绪: kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s"
echo "  2. 安装 KubeVirt CR: ./scripts/fix-kubevirt-installation.sh (选择 A)"
echo "  3. 安装 CDI: ./scripts/install-cdi.sh"

