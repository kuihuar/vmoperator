#!/bin/bash

# 修复 pause 镜像问题

echo "=== 修复 pause 镜像问题 ==="

# 1. 检查现有镜像
echo -e "\n1. 检查现有 pause 镜像..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml

EXISTING_PAUSE=$(crictl images | grep -i pause | head -1 | awk '{print $1":"$2}')
if [ -n "$EXISTING_PAUSE" ]; then
    echo "✓ 找到 pause 镜像: $EXISTING_PAUSE"
else
    echo "✗ 未找到 pause 镜像"
    exit 1
fi

# 2. 尝试拉取 rancher/mirrored-pause:3.6
echo -e "\n2. 尝试拉取 rancher/mirrored-pause:3.6..."
if crictl pull rancher/mirrored-pause:3.6 2>/dev/null; then
    echo "✓ 成功拉取 rancher/mirrored-pause:3.6"
    SUCCESS=true
else
    echo "⚠️  无法拉取 rancher/mirrored-pause:3.6"
    SUCCESS=false
fi

# 3. 如果拉取失败，尝试使用现有镜像
if [ "$SUCCESS" = false ]; then
    echo -e "\n3. 使用现有镜像作为替代..."
    echo "   注意: k3s 需要 rancher/mirrored-pause:3.6，但系统有 $EXISTING_PAUSE"
    echo "   可以尝试以下方法："
    echo ""
    echo "   方法 A: 配置 k3s 使用系统默认镜像"
    echo "   方法 B: 删除 Pod 让 k3s 重新尝试"
    echo "   方法 C: 手动 tag 镜像（如果 containerd 支持）"
    
    # 检查是否可以 tag
    if command -v ctr > /dev/null 2>&1; then
        echo -e "\n   尝试使用 ctr tag 镜像..."
        IMAGE_ID=$(crictl images | grep "$EXISTING_PAUSE" | awk '{print $3}')
        if [ -n "$IMAGE_ID" ]; then
            echo "   镜像 ID: $IMAGE_ID"
            echo "   尝试 tag: rancher/mirrored-pause:3.6"
            # 注意：ctr tag 需要完整的镜像引用
            # 这里只是示例，实际可能需要不同的格式
            echo "   运行: sudo ctr -n k8s.io images tag $EXISTING_PAUSE rancher/mirrored-pause:3.6"
            read -p "   是否尝试 tag? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if sudo ctr -n k8s.io images tag "$EXISTING_PAUSE" rancher/mirrored-pause:3.6 2>/dev/null; then
                    echo "   ✓ Tag 成功"
                    SUCCESS=true
                else
                    echo "   ✗ Tag 失败，可能需要不同的方法"
                fi
            fi
        fi
    fi
fi

# 4. 删除 Pod 重新创建
if [ "$SUCCESS" = true ] || [ -n "$EXISTING_PAUSE" ]; then
    echo -e "\n4. 删除 Pod 重新创建..."
    kubectl delete pod -n kubevirt -l app=virt-operator
    echo "✓ Pod 已删除，等待重新创建..."
    echo ""
    echo "观察 Pod 状态（30 秒）:"
    timeout 30 kubectl get pods -n kubevirt -w 2>/dev/null || kubectl get pods -n kubevirt
else
    echo -e "\n4. 无法解决 pause 镜像问题"
    echo "   建议："
    echo "   1. 配置代理或 VPN"
    echo "   2. 手动下载镜像"
    echo "   3. 或暂时跳过 KubeVirt，继续其他工作"
fi

echo -e "\n=== 完成 ==="

