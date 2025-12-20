#!/bin/bash

# 强制修复镜像源配置

echo "=== 强制修复镜像源配置 ==="

# 1. 检查系统代理环境变量
echo -e "\n1. 检查系统代理环境变量..."
echo "HTTP_PROXY: ${HTTP_PROXY:-未设置}"
echo "HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
echo "http_proxy: ${http_proxy:-未设置}"
echo "https_proxy: ${https_proxy:-未设置}"
if [ -f /etc/environment ]; then
    echo "检查 /etc/environment:"
    grep -i proxy /etc/environment || echo "  未找到代理配置"
fi

# 2. 检查 k3s systemd 服务文件中的环境变量
echo -e "\n2. 检查 k3s systemd 服务配置..."
if [ -f /etc/systemd/system/k3s.service ]; then
    echo "k3s.service 中的环境变量:"
    sudo grep -i "Environment\|proxy" /etc/systemd/system/k3s.service || echo "  未找到代理配置"
elif [ -f /etc/systemd/system/k3s.service.d/k3s.conf ]; then
    echo "k3s.conf 中的环境变量:"
    sudo grep -i "Environment\|proxy" /etc/systemd/system/k3s.service.d/k3s.conf || echo "  未找到代理配置"
fi

# 3. 检查当前配置
echo -e "\n3. 检查当前配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "当前配置:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "配置文件不存在"
fi

# 4. 检查 containerd 配置
echo -e "\n4. 检查 containerd 配置..."
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "⚠️  发现 containerd 配置文件"
    echo "检查代理配置:"
    sudo grep -i "proxy\|mirror\|registry" /var/lib/rancher/k3s/agent/etc/containerd/config.toml | head -20
fi

# 5. 清理代理配置
echo -e "\n5. 清理代理配置..."

# 清理 systemd 服务文件中的代理环境变量
if [ -f /etc/systemd/system/k3s.service ]; then
    if sudo grep -qi "proxy" /etc/systemd/system/k3s.service; then
        echo "⚠️  发现 k3s.service 中有代理配置，需要手动清理"
        echo "   文件位置: /etc/systemd/system/k3s.service"
    fi
fi

# 清理 /etc/environment 中的代理配置（如果存在）
if [ -f /etc/environment ] && grep -qi "proxy" /etc/environment; then
    echo "⚠️  发现 /etc/environment 中有代理配置"
    echo "   建议手动检查并清理: sudo vim /etc/environment"
fi

# 6. 完全清理并重新配置
echo -e "\n6. 完全清理并重新配置..."

# 删除所有可能的配置文件
sudo rm -f /etc/rancher/k3s/registries.yaml
echo "✓ 已删除 /etc/rancher/k3s/registries.yaml"

# 检查并清理 containerd 配置中的旧镜像源
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "⚠️  containerd 配置文件会在 k3s 重启时重新生成"
fi

# 7. 创建新的配置文件（只使用阿里云，不使用代理）
echo -e "\n7. 创建新的配置文件（只使用阿里云镜像源，无代理）..."
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
  registry-1.docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
EOF

echo "✓ 新配置已创建"
cat /etc/rancher/k3s/registries.yaml

# 8. 停止 k3s（确保完全停止）
echo -e "\n8. 停止 k3s..."
sudo systemctl stop k3s
sleep 5

# 9. 清理可能的缓存
echo -e "\n9. 清理可能的缓存..."
# containerd 的配置会在 k3s 启动时重新生成，这里不需要手动清理

# 10. 启动 k3s
echo -e "\n10. 启动 k3s..."
sudo systemctl start k3s
echo "等待 k3s 就绪..."
sleep 20

if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ k3s 已就绪"
else
    echo "⚠️  k3s 可能还在启动中，等待更长时间..."
    sleep 10
    kubectl get nodes || echo "k3s 可能启动失败，请检查: sudo systemctl status k3s"
fi

# 11. 验证配置是否生效
echo -e "\n11. 验证配置是否生效..."
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "containerd 配置中的镜像源:"
    sudo grep -A 5 "mirrors\|registry" /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -i "aliyun\|e0hhb5lk" || echo "  未找到新镜像源，可能需要检查配置格式"
    echo ""
    echo "检查是否还有代理配置:"
    sudo grep -i "proxy\|ustc" /var/lib/rancher/k3s/agent/etc/containerd/config.toml || echo "  ✓ 未发现代理配置"
fi

# 12. 确保本地镜像已 tag
echo -e "\n12. 确保本地镜像已 tag..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if ! crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "Tag 本地 pause 镜像..."
    sudo ctr -n k8s.io images tag \
        registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
        rancher/mirrored-pause:3.6 2>&1 | head -3
fi

# 13. 删除 Pod 重新创建
echo -e "\n13. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator --force --grace-period=0 2>/dev/null || true
sleep 5
kubectl delete pod -n kubevirt -l app=virt-operator 2>/dev/null || true

echo -e "\n观察 Pod 状态:"
kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 仍然无法启动，检查："
echo "  1. 系统代理环境变量: env | grep -i proxy"
echo "  2. k3s systemd 服务: sudo systemctl show k3s | grep -i proxy"
echo "  3. k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'mirror\|registry\|pause\|proxy'"
echo "  4. containerd 配置: sudo cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -A 10 -i 'mirror\|proxy'"
echo "  5. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
echo ""
echo "如果仍然看到 'docker.mirrors.ustc.edu.cn' 错误，说明有代理配置未清理："
echo "  1. 检查 /etc/environment: cat /etc/environment | grep -i proxy"
echo "  2. 检查 ~/.bashrc 或 ~/.profile: grep -i proxy ~/.bashrc ~/.profile"
echo "  3. 检查 k3s systemd override: sudo systemctl edit k3s"

