#!/bin/bash

# 验证所有镜像是否可用

echo "=== 验证所有镜像 ==="

# 1. 检查 pause 镜像
echo -e "\n1. 检查 pause 镜像..."
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ rancher/mirrored-pause:3.6 存在"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
else
    echo "❌ rancher/mirrored-pause:3.6 不存在"
    echo "检查其他 pause 镜像..."
    sudo crictl images | grep -i pause || echo "  未找到任何 pause 镜像"
fi

# 2. 检查 virt-operator 镜像
echo -e "\n2. 检查 virt-operator 镜像..."
if sudo crictl images | grep -q "virt-operator"; then
    echo "✓ virt-operator 镜像存在:"
    sudo crictl images | grep virt-operator
else
    echo "❌ virt-operator 镜像不存在"
fi

# 3. 检查所有 kubevirt 相关镜像
echo -e "\n3. 检查所有 kubevirt 相关镜像..."
KUBEVIRT_IMGS=$(sudo crictl images | grep -i "kubevirt\|virt")
if [ -n "$KUBEVIRT_IMGS" ]; then
    echo "找到以下 kubevirt 镜像:"
    echo "$KUBEVIRT_IMGS"
else
    echo "⚠️  未找到 kubevirt 镜像"
fi

# 4. 检查所有镜像列表
echo -e "\n4. 所有镜像列表:"
sudo crictl images

# 5. 验证镜像在 containerd 中可用
echo -e "\n5. 验证镜像在 containerd 中可用..."
if sudo ctr -n k8s.io images list | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ pause 镜像在 containerd 中可用"
else
    echo "⚠️  pause 镜像在 containerd 中不可用"
fi

# 6. 检查 k3s 配置
echo -e "\n6. 检查 k3s 配置..."
echo "镜像源配置:"
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    cat /etc/rancher/k3s/registries.yaml
else
    echo "  未配置镜像源（将使用本地镜像或直接访问 Docker Hub）"
fi

echo -e "\n代理配置:"
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    PROXY=$(sudo systemctl show k3s | grep -i "proxy" || echo "  未配置代理")
    echo "$PROXY"
else
    echo "  k3s 服务未运行"
fi

# 7. 检查 k3s 状态
echo -e "\n7. 检查 k3s 状态..."
if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ k3s 集群正常"
    kubectl get nodes
else
    echo "❌ k3s 集群异常"
    echo "检查 k3s 服务状态:"
    sudo systemctl status k3s --no-pager | head -10
fi

# 8. 检查 virt-operator Pods
echo -e "\n8. 检查 virt-operator Pods..."
if kubectl get pods -n kubevirt -l app=virt-operator 2>/dev/null | grep -q virt-operator; then
    echo "virt-operator Pods 状态:"
    kubectl get pods -n kubevirt -l app=virt-operator
    
    # 检查 Pod 是否 Running
    RUNNING=$(kubectl get pods -n kubevirt -l app=virt-operator -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
    if echo "$RUNNING" | grep -q "Running"; then
        echo "✓ 至少有一个 Pod 正在运行"
    else
        echo "⚠️  没有 Pod 在运行状态"
        echo "检查 Pod 详情..."
        for pod in $(kubectl get pods -n kubevirt -l app=virt-operator -o jsonpath='{.items[*].metadata.name}'); do
            echo -e "\nPod: $pod"
            kubectl describe pod -n kubevirt "$pod" 2>/dev/null | grep -A 5 "Events:" | head -10
        done
    fi
else
    echo "⚠️  未找到 virt-operator Pods"
    echo "检查 kubevirt namespace:"
    kubectl get pods -n kubevirt 2>/dev/null || echo "  kubevirt namespace 可能不存在"
fi

# 9. 检查最新事件
echo -e "\n9. 检查最新事件..."
if kubectl get events -n kubevirt 2>/dev/null | grep -q .; then
    echo "kubevirt namespace 最新事件:"
    kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -10
else
    echo "  无事件"
fi

# 10. 测试创建 Pod（使用 pause 镜像）
echo -e "\n10. 测试创建 Pod（使用 pause 镜像）..."
cat > /tmp/test-pause-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pause-verify
  namespace: default
spec:
  containers:
  - name: pause
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
EOF

echo "创建测试 Pod..."
kubectl apply -f /tmp/test-pause-pod.yaml > /dev/null 2>&1

sleep 5

POD_STATUS=$(kubectl get pod test-pause-verify -n default -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$POD_STATUS" = "Running" ]; then
    echo "✓ 测试 Pod 运行成功，镜像可用"
elif [ "$POD_STATUS" = "Pending" ]; then
    echo "⚠️  测试 Pod 处于 Pending 状态"
    kubectl describe pod test-pause-verify -n default 2>/dev/null | grep -A 10 "Events:" | head -15
else
    echo "⚠️  测试 Pod 状态: $POD_STATUS"
    kubectl describe pod test-pause-verify -n default 2>/dev/null | grep -A 10 "Events:" | head -15
fi

# 清理测试 Pod
kubectl delete pod test-pause-verify -n default --force --grace-period=0 > /dev/null 2>&1 || true

# 11. 总结
echo -e "\n=== 验证总结 ==="
echo ""
echo "镜像状态:"
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "  ✓ pause 镜像存在"
else
    echo "  ❌ pause 镜像不存在"
fi

if sudo crictl images | grep -q "virt-operator"; then
    echo "  ✓ virt-operator 镜像存在"
else
    echo "  ⚠️  virt-operator 镜像不存在（可能需要拉取）"
fi

echo ""
echo "k3s 状态:"
if kubectl get nodes > /dev/null 2>&1; then
    echo "  ✓ k3s 集群正常"
else
    echo "  ❌ k3s 集群异常"
fi

echo ""
echo "virt-operator Pods:"
if kubectl get pods -n kubevirt -l app=virt-operator 2>/dev/null | grep -q Running; then
    echo "  ✓ virt-operator Pods 正在运行"
else
    echo "  ⚠️  virt-operator Pods 未运行"
    echo ""
    echo "如果 Pod 无法启动，检查："
    echo "  1. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
    echo "  2. Pod 详情: kubectl describe pod -n kubevirt -l app=virt-operator"
    echo "  3. k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'pause\|error'"
fi

echo ""
echo "=== 验证完成 ==="

