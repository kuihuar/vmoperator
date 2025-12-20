#!/bin/bash

# 快速检查镜像

echo "=== 快速检查镜像 ==="

# 方法 1: 使用 sudo crictl（推荐）
echo -e "\n方法 1: 使用 sudo crictl images"
sudo crictl images

# 方法 2: 配置用户 crictl
echo -e "\n方法 2: 配置用户 crictl..."
mkdir -p ~/.config/crictl
cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
EOF
chmod 600 ~/.config/crictl/crictl.yaml

echo "✓ 已配置用户 crictl"
echo "现在可以运行: crictl images"

# 方法 3: 使用 ctr（containerd 直接命令）
echo -e "\n方法 3: 使用 ctr images list (k8s.io namespace)"
sudo ctr -n k8s.io images list

echo -e "\n=== 检查 pause 镜像 ==="
echo "查找 pause 相关镜像:"
sudo crictl images | grep -i pause || sudo ctr -n k8s.io images list | grep -i pause

echo -e "\n查找 rancher/mirrored-pause:3.6:"
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 找到 rancher/mirrored-pause:3.6"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  未找到 rancher/mirrored-pause:3.6"
    echo ""
    echo "如果找到其他 pause 镜像，可以 tag:"
    PAUSE_IMG=$(sudo crictl images | grep pause | head -1 | awk '{print $1":"$2}' 2>/dev/null)
    if [ -n "$PAUSE_IMG" ] && [ "$PAUSE_IMG" != ":" ]; then
        echo "  sudo ctr -n k8s.io images tag $PAUSE_IMG rancher/mirrored-pause:3.6"
    fi
fi

