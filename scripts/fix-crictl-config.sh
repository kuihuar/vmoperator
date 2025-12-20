#!/bin/bash

# 快速修复 crictl 配置

echo "=== 修复 crictl 配置 ==="

# 1. 创建用户配置文件
echo -e "\n1. 创建用户配置文件..."
mkdir -p ~/.config/crictl
cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
echo "✓ ~/.config/crictl/crictl.yaml"

# 2. 创建系统级配置文件（更可靠）
echo -e "\n2. 创建系统级配置文件..."
sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
sudo chmod 644 /etc/crictl.yaml
echo "✓ /etc/crictl.yaml"

# 3. 设置环境变量
echo -e "\n3. 设置环境变量..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if ! grep -q "CRICTL_CONFIG" ~/.bashrc 2>/dev/null; then
    echo 'export CRICTL_CONFIG=~/.config/crictl/crictl.yaml' >> ~/.bashrc
    echo "✓ 已添加到 ~/.bashrc"
fi

# 4. 配置 socket 权限
echo -e "\n4. 配置 socket 权限..."
if [ -S /run/k3s/containerd/containerd.sock ]; then
    sudo chmod 666 /run/k3s/containerd/containerd.sock
    echo "✓ Socket 权限已设置"
else
    echo "⚠️  Socket 文件不存在"
fi

# 5. 测试
echo -e "\n5. 测试 crictl..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if crictl version > /dev/null 2>&1; then
    echo "✓ crictl 配置成功！"
    echo ""
    crictl version
else
    echo "⚠️  仍需要测试，尝试拉取镜像..."
    if crictl pull quay.io/kubevirt/virt-operator:v1.2.0 2>&1 | head -5; then
        echo "✓ 镜像拉取成功！"
    else
        echo "⚠️  如果仍有问题，请："
        echo "  1. 运行: source ~/.bashrc"
        echo "  2. 或重新登录"
        echo "  3. 或使用: CRICTL_CONFIG=~/.config/crictl/crictl.yaml crictl version"
    fi
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果 crictl 仍无法工作，请运行:"
echo "  export CRICTL_CONFIG=~/.config/crictl/crictl.yaml"
echo "  crictl version"

