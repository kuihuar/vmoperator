#!/bin/bash

# 检查系统镜像状态

echo "=== 检查系统镜像状态 ==="

# 1. 检查 crictl 镜像
echo -e "\n1. 检查 crictl 镜像列表:"
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if crictl images > /dev/null 2>&1; then
    echo "所有镜像:"
    crictl images
    echo ""
    echo "pause 相关镜像:"
    crictl images | grep -i pause || echo "  没有找到 pause 镜像"
else
    echo "⚠️  crictl 无法工作"
fi

# 2. 检查 k3s 镜像目录
echo -e "\n2. 检查 k3s 镜像缓存:"
if [ -d /var/lib/rancher/k3s/agent/images ]; then
    echo "k3s 镜像目录内容:"
    sudo ls -lh /var/lib/rancher/k3s/agent/images/ | head -10
    echo ""
    echo "是否有 pause 镜像:"
    sudo ls -la /var/lib/rancher/k3s/agent/images/ | grep -i pause || echo "  没有找到 pause 镜像文件"
else
    echo "⚠️  k3s 镜像目录不存在"
fi

# 3. 检查 containerd 镜像
echo -e "\n3. 检查 containerd 镜像:"
if command -v ctr > /dev/null 2>&1; then
    sudo ctr -n k8s.io images ls | grep -i pause || echo "  没有找到 pause 镜像"
else
    echo "⚠️  ctr 命令不可用"
fi

# 4. 检查当前 Pod 状态
echo -e "\n4. 当前 Pod 状态:"
kubectl get pods -n kubevirt 2>/dev/null || echo "  kubevirt 命名空间或 Pods 不存在"

# 5. 建议
echo -e "\n=== 建议 ==="
if crictl images | grep -q -i pause; then
    echo "✓ 系统已有 pause 镜像，可以尝试："
    echo "  1. 删除 Pod 重新创建: kubectl delete pod -n kubevirt -l app=virt-operator"
    echo "  2. 检查 k3s 配置是否正确识别镜像"
else
    echo "⚠️  系统没有 pause 镜像，需要："
    echo "  1. 配置代理或 VPN"
    echo "  2. 手动下载镜像"
    echo "  3. 或暂时跳过 KubeVirt，先测试其他功能（CDI、Wukong CRD 等）"
fi

