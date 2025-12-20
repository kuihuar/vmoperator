#!/bin/bash

# 诊断 Pod 无法启动的问题

echo "=== 诊断 Pod 无法启动问题 ==="

# 1. 检查镜像
echo -e "\n1. 检查 pause 镜像:"
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl images | grep -i pause || echo "  没有找到 pause 镜像"

# 2. 检查 k3s 配置
echo -e "\n2. 检查 k3s 镜像源配置:"
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "⚠️  配置文件仍存在:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "✓ 配置文件已删除（k3s 将使用 Docker Hub）"
fi

# 3. 检查 Pod 事件
echo -e "\n3. 最新 Pod 事件:"
POD_NAME=$(kubectl get pods -n kubevirt -l app=virt-operator -o name | head -1 | cut -d/ -f2)
if [ -n "$POD_NAME" ]; then
    echo "Pod: $POD_NAME"
    kubectl describe pod -n kubevirt $POD_NAME | grep -A 30 Events | tail -20
else
    echo "未找到 Pod"
fi

# 4. 检查所有事件
echo -e "\n4. 最近 10 个事件:"
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10

# 5. 检查 k3s 服务状态
echo -e "\n5. k3s 服务状态:"
sudo systemctl status k3s --no-pager | head -10

# 6. 检查 k3s 日志（最近相关）
echo -e "\n6. k3s 日志（最近 pause 相关）:"
sudo journalctl -u k3s -n 50 --no-pager | grep -i "pause\|registry\|pull" | tail -10 || echo "  没有找到相关日志"

# 7. 测试从 Docker Hub 拉取
echo -e "\n7. 测试从 Docker Hub 拉取镜像:"
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
echo "尝试拉取 rancher/mirrored-pause:3.6..."
crictl pull rancher/mirrored-pause:3.6 2>&1 | head -5

echo -e "\n=== 诊断完成 ==="

