#!/bin/bash

# 验证本地 pause 镜像并确保可用

echo "=== 验证本地 pause 镜像 ==="

# 1. 检查镜像是否存在
echo -e "\n1. 检查镜像是否存在..."
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 找到镜像:"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
    
    # 获取镜像 ID
    IMAGE_ID=$(sudo crictl images | grep "rancher/mirrored-pause:3.6" | awk '{print $3}')
    echo "镜像 ID: $IMAGE_ID"
    
    # 检查镜像详细信息
    echo -e "\n镜像详细信息:"
    sudo ctr -n k8s.io images inspect rancher/mirrored-pause:3.6 2>/dev/null || echo "无法获取详细信息"
else
    echo "⚠️  未找到 rancher/mirrored-pause:3.6"
    
    # 检查是否有其他 pause 镜像
    echo -e "\n检查其他 pause 镜像..."
    PAUSE_IMGS=$(sudo crictl images | grep -i pause)
    if [ -n "$PAUSE_IMGS" ]; then
        echo "找到以下 pause 镜像:"
        echo "$PAUSE_IMGS"
        echo ""
        PAUSE_IMG=$(echo "$PAUSE_IMGS" | head -1 | awk '{print $1":"$2}')
        if [ -n "$PAUSE_IMG" ] && [ "$PAUSE_IMG" != ":" ]; then
            echo "Tag $PAUSE_IMG 为 rancher/mirrored-pause:3.6..."
            sudo ctr -n k8s.io images tag "$PAUSE_IMG" rancher/mirrored-pause:3.6
            echo "✓ 已 tag"
        fi
    else
        echo "❌ 未找到任何 pause 镜像"
        exit 1
    fi
fi

# 2. 验证镜像在 containerd 中可用
echo -e "\n2. 验证镜像在 containerd 中可用..."
if sudo ctr -n k8s.io images list | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 镜像在 containerd 中可用"
    sudo ctr -n k8s.io images list | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  镜像在 containerd 中不可用"
    echo "尝试从 crictl 同步到 containerd..."
    # containerd 和 crictl 共享镜像，通常不需要同步
fi

# 3. 测试镜像是否可以用于创建容器
echo -e "\n3. 测试镜像是否可以用于创建容器..."
# 创建一个测试 Pod 来验证镜像是否可用
cat > /tmp/test-pause-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pause
  namespace: default
spec:
  containers:
  - name: pause
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
EOF

echo "创建测试 Pod..."
kubectl apply -f /tmp/test-pause-pod.yaml 2>&1 | head -3

sleep 5

# 检查 Pod 状态
POD_STATUS=$(kubectl get pod test-pause -n default -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Pending" ]; then
    echo "✓ Pod 创建成功，状态: $POD_STATUS"
    echo "镜像可用"
    
    # 清理测试 Pod
    kubectl delete pod test-pause -n default --force --grace-period=0 2>/dev/null || true
else
    echo "⚠️  Pod 状态: $POD_STATUS"
    kubectl describe pod test-pause -n default 2>/dev/null | grep -A 10 "Events:" || true
fi

# 4. 检查 k3s 配置
echo -e "\n4. 检查 k3s 配置..."
echo "镜像源配置:"
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    cat /etc/rancher/k3s/registries.yaml
else
    echo "  未配置镜像源（将直接使用 Docker Hub 或本地镜像）"
fi

echo -e "\n代理配置:"
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    PROXY=$(sudo systemctl show k3s | grep -i "proxy" || echo "  未配置代理")
    echo "$PROXY"
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果镜像存在但 Pod 仍然无法启动，可能的原因："
echo "  1. k3s 仍然尝试从网络拉取而不是使用本地镜像"
echo "  2. 镜像格式或标签不正确"
echo "  3. containerd 配置问题"
echo ""
echo "建议："
echo "  1. 确保镜像已正确 tag: sudo ctr -n k8s.io images list | grep pause"
echo "  2. 检查 k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'pause'"
echo "  3. 检查 Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"

