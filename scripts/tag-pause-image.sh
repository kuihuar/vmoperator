#!/bin/bash

# 直接 tag pause 镜像

echo "=== Tag pause 镜像 ==="

# 1. 检查现有镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
EXISTING_PAUSE="registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6"
TARGET_PAUSE="rancher/mirrored-pause:3.6"

echo "源镜像: $EXISTING_PAUSE"
echo "目标镜像: $TARGET_PAUSE"
echo ""

# 2. 使用 ctr tag
echo "执行 tag 操作..."
if sudo ctr -n k8s.io images tag "$EXISTING_PAUSE" "$TARGET_PAUSE" 2>&1; then
    echo "✓ Tag 成功"
else
    echo "✗ Tag 失败，尝试其他方法..."
    
    # 方法 2: 使用完整的镜像引用
    IMAGE_ID=$(crictl images | grep "$EXISTING_PAUSE" | awk '{print $3}')
    if [ -n "$IMAGE_ID" ]; then
        echo "尝试使用镜像 ID: $IMAGE_ID"
        # 使用 ctr images tag 的完整格式
        if sudo ctr -n k8s.io images tag "${EXISTING_PAUSE}@sha256:$(echo $IMAGE_ID | cut -d: -f2)" "$TARGET_PAUSE" 2>&1; then
            echo "✓ Tag 成功（使用镜像 ID）"
        else
            echo "✗ Tag 仍然失败"
            echo ""
            echo "尝试手动方法："
            echo "  1. 检查镜像详细信息:"
            echo "     sudo ctr -n k8s.io images ls | grep pause"
            echo ""
            echo "  2. 使用完整镜像引用 tag:"
            echo "     sudo ctr -n k8s.io images tag <完整镜像引用> $TARGET_PAUSE"
            exit 1
        fi
    fi
fi

# 3. 验证
echo -e "\n验证 tag 结果:"
crictl images | grep pause

# 4. 删除 Pod
echo -e "\n删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除"

echo -e "\n观察 Pod 状态（30 秒）:"
timeout 30 kubectl get pods -n kubevirt -w 2>/dev/null || kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="

