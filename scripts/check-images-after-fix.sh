#!/bin/bash

# 检查修复后的镜像状态

echo "=== 检查修复后的镜像状态 ==="

# 1. 检查 crictl 配置
echo -e "\n1. 检查 crictl 配置..."
if [ -f ~/.config/crictl/crictl.yaml ]; then
    echo "用户配置:"
    cat ~/.config/crictl/crictl.yaml
elif [ -f /etc/crictl/crictl.yaml ]; then
    echo "系统配置:"
    sudo cat /etc/crictl/crictl.yaml
else
    echo "⚠️  未找到 crictl 配置文件"
    echo "尝试使用环境变量..."
    export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
    mkdir -p ~/.config/crictl
    cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
EOF
    echo "✓ 已创建用户配置"
fi

# 2. 设置正确的运行时端点
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if [ ! -f ~/.config/crictl/crictl.yaml ]; then
    mkdir -p ~/.config/crictl
    cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
EOF
fi

# 3. 检查镜像列表
echo -e "\n2. 检查镜像列表..."
echo "使用 crictl images:"
crictl images 2>&1 || {
    echo "⚠️  crictl images 失败，尝试使用 sudo:"
    sudo crictl images 2>&1 | head -20
}

# 4. 检查 pause 镜像
echo -e "\n3. 检查 pause 镜像..."
if crictl images 2>/dev/null | grep -q "pause"; then
    echo "找到 pause 相关镜像:"
    crictl images 2>/dev/null | grep pause
else
    echo "使用 sudo 检查:"
    sudo crictl images 2>/dev/null | grep pause || echo "  未找到 pause 镜像"
fi

# 5. 检查 rancher/mirrored-pause:3.6
echo -e "\n4. 检查 rancher/mirrored-pause:3.6..."
if crictl images 2>/dev/null | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 找到 rancher/mirrored-pause:3.6"
    crictl images 2>/dev/null | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  未找到 rancher/mirrored-pause:3.6"
    echo "检查是否有其他 pause 镜像可以 tag..."
    if crictl images 2>/dev/null | grep -q "pause"; then
        echo "找到以下 pause 镜像:"
        crictl images 2>/dev/null | grep pause
        echo ""
        echo "可以运行以下命令 tag:"
        PAUSE_IMG=$(crictl images 2>/dev/null | grep pause | head -1 | awk '{print $1":"$2}')
        if [ -n "$PAUSE_IMG" ]; then
            echo "  sudo ctr -n k8s.io images tag $PAUSE_IMG rancher/mirrored-pause:3.6"
        fi
    fi
fi

# 6. 检查 k3s 代理配置
echo -e "\n5. 检查 k3s 代理配置..."
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    if sudo systemctl show k3s | grep -qi "proxy"; then
        echo "⚠️  仍然发现代理配置:"
        sudo systemctl show k3s | grep -i "proxy"
    else
        echo "✓ 未发现代理配置"
    fi
else
    echo "k3s 服务未运行"
fi

# 7. 检查 Pod 状态
echo -e "\n6. 检查 Pod 状态..."
if kubectl get pods -n kubevirt 2>/dev/null | grep -q virt-operator; then
    echo "virt-operator Pods:"
    kubectl get pods -n kubevirt -l app=virt-operator
    echo ""
    echo "最新事件:"
    kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -5
else
    echo "未找到 virt-operator Pods"
fi

echo -e "\n=== 检查完成 ==="

