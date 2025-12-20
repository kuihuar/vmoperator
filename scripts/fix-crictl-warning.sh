#!/bin/bash

# 消除 crictl 警告信息

echo "=== 消除 crictl 警告 ==="

# 警告原因：crictl 在查找配置文件时会尝试访问 k3s 的配置目录
# 虽然不影响使用，但可以通过以下方法消除警告

echo -e "\n1. 检查当前配置..."
if [ -f ~/.config/crictl/crictl.yaml ]; then
    echo "✓ 用户配置文件存在: ~/.config/crictl/crictl.yaml"
else
    echo "✗ 用户配置文件不存在，创建中..."
    mkdir -p ~/.config/crictl
    cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
    echo "✓ 已创建"
fi

echo -e "\n2. 设置环境变量（推荐）..."
# 方法 1: 使用环境变量显式指定配置文件
if ! grep -q "CRICTL_CONFIG" ~/.bashrc 2>/dev/null; then
    echo 'export CRICTL_CONFIG=~/.config/crictl/crictl.yaml' >> ~/.bashrc
    echo "✓ 已添加到 ~/.bashrc"
    echo "  运行 'source ~/.bashrc' 使配置生效"
else
    echo "✓ 环境变量已存在"
fi

# 方法 2: 创建系统级配置文件（优先级更高）
echo -e "\n3. 创建系统级配置文件（可选）..."
if [ ! -f /etc/crictl.yaml ]; then
    read -p "是否创建系统级配置文件 /etc/crictl.yaml? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
        sudo chmod 644 /etc/crictl.yaml
        echo "✓ 系统级配置文件已创建"
    fi
else
    echo "✓ 系统级配置文件已存在"
fi

# 方法 3: 创建别名（最简单）
echo -e "\n4. 创建别名（消除警告）..."
if ! grep -q "alias crictl=" ~/.bashrc 2>/dev/null; then
    echo 'alias crictl="CRICTL_CONFIG=~/.config/crictl/crictl.yaml /usr/local/bin/crictl 2>/dev/null || CRICTL_CONFIG=~/.config/crictl/crictl.yaml crictl"' >> ~/.bashrc
    echo "✓ 别名已添加到 ~/.bashrc"
    echo "  运行 'source ~/.bashrc' 使别名生效"
else
    echo "✓ 别名已存在"
fi

echo -e "\n=== 完成 ==="
echo ""
echo "消除警告的方法："
echo "  1. 使用环境变量: export CRICTL_CONFIG=~/.config/crictl/crictl.yaml"
echo "  2. 使用别名: source ~/.bashrc 然后直接使用 crictl"
echo "  3. 系统级配置: /etc/crictl.yaml（已创建）"
echo ""
echo "测试（应该没有警告）:"
echo "  source ~/.bashrc"
echo "  crictl images"

