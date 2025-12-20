#!/bin/bash

# 配置 crictl 无需 sudo

echo "=== 配置 crictl 无需 sudo ==="

# 1. 创建配置文件
echo -e "\n1. 创建 crictl 配置文件..."

# crictl 配置文件查找顺序：
# 1. $CRICTL_CONFIG (环境变量)
# 2. $XDG_CONFIG_HOME/crictl/crictl.yaml
# 3. $HOME/.config/crictl/crictl.yaml
# 4. /etc/crictl.yaml
# 5. /var/lib/rancher/k3s/agent/etc/crictl.yaml (k3s 特定)

# 方法 1: 用户配置文件
mkdir -p ~/.config/crictl
cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
echo "✓ 用户配置文件已创建: ~/.config/crictl/crictl.yaml"

# 方法 2: 系统级配置文件（如果用户配置不工作）
echo -e "\n2. 创建系统级配置文件（可选）..."
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
    echo "✓ 系统级配置文件已创建: /etc/crictl.yaml"
fi

# 方法 3: 设置环境变量（备用）
echo -e "\n3. 设置环境变量（备用方案）..."
if ! grep -q "CRICTL_CONFIG" ~/.bashrc 2>/dev/null; then
    echo 'export CRICTL_CONFIG=~/.config/crictl/crictl.yaml' >> ~/.bashrc
    echo "✓ 环境变量已添加到 ~/.bashrc"
    echo "  运行 'source ~/.bashrc' 或重新登录使环境变量生效"
fi

# 4. 检查 socket 文件
echo -e "\n4. 检查 socket 文件..."
if [ -S /run/k3s/containerd/containerd.sock ]; then
    echo "✓ Socket 文件存在: /run/k3s/containerd/containerd.sock"
    CURRENT_PERMS=$(stat -c "%a" /run/k3s/containerd/containerd.sock 2>/dev/null || stat -f "%OLp" /run/k3s/containerd/containerd.sock)
    echo "  当前权限: $CURRENT_PERMS"
else
    echo "✗ Socket 文件不存在: /run/k3s/containerd/containerd.sock"
    echo "  查找其他可能的 socket 位置..."
    SOCKET_PATH=$(sudo find /run -name "containerd.sock" 2>/dev/null | head -1)
    if [ -n "$SOCKET_PATH" ]; then
        echo "  找到: $SOCKET_PATH"
        echo "  请手动更新配置文件中的路径"
    else
        echo "  未找到 containerd socket，请检查 k3s 是否运行"
        exit 1
    fi
fi

# 5. 配置 socket 权限
echo -e "\n5. 配置 socket 权限..."

# 检查是否有 k3s 组
if getent group k3s > /dev/null 2>&1; then
    echo "  发现 k3s 组，将用户添加到组..."
    if groups | grep -q k3s; then
        echo "  ✓ 用户已在 k3s 组中"
    else
        sudo usermod -aG k3s $USER
        echo "  ✓ 用户已添加到 k3s 组"
        echo "  ⚠️  需要重新登录或运行 'newgrp k3s' 使组权限生效"
    fi
else
    echo "  k3s 组不存在，创建 systemd override..."
    sudo mkdir -p /etc/systemd/system/k3s.service.d/
    sudo tee /etc/systemd/system/k3s.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStartPost=/bin/chmod 666 /run/k3s/containerd/containerd.sock
EOF
    sudo systemctl daemon-reload
    echo "  ✓ systemd override 已创建"
    echo "  ⚠️  需要重启 k3s 使配置生效: sudo systemctl restart k3s"
fi

# 6. 临时修改权限（立即生效）
echo -e "\n6. 临时修改 socket 权限（立即生效）..."
if sudo chmod 666 /run/k3s/containerd/containerd.sock 2>/dev/null; then
    echo "  ✓ Socket 权限已修改（临时）"
else
    echo "  ⚠️  无法修改权限，可能需要重启 k3s"
fi

# 7. 测试
echo -e "\n7. 测试 crictl..."
if crictl version > /dev/null 2>&1; then
    echo "  ✓ crictl 可以正常工作（无需 sudo）"
    echo ""
    crictl version
else
    echo "  ⚠️  crictl 仍需要 sudo，尝试使用 sudo 测试..."
    if sudo crictl version > /dev/null 2>&1; then
        echo "  ✓ crictl 可以使用（需要 sudo）"
        echo ""
        echo "  如果已添加到 k3s 组，请："
        echo "    1. 重新登录，或"
        echo "    2. 运行: newgrp k3s"
        echo ""
        echo "  如果创建了 systemd override，请："
        echo "    1. 重启 k3s: sudo systemctl restart k3s"
    else
        echo "  ✗ crictl 无法工作，请检查配置"
    fi
fi

echo -e "\n=== 配置完成 ==="
echo ""
echo "如果 crictl 仍需要 sudo，请："
echo "  1. 如果添加了用户组: 重新登录或运行 'newgrp k3s'"
echo "  2. 如果创建了 systemd override: 重启 k3s 'sudo systemctl restart k3s'"
echo "  3. 临时方案: 使用 'sudo crictl' 或创建别名"

