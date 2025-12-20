#!/bin/bash

# 修复 k3s 镜像源配置

echo "=== 修复 k3s 镜像源配置 ==="

# 1. 检查当前配置
echo -e "\n1. 检查当前镜像源配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "当前配置:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "未找到配置文件"
fi

# 2. 测试镜像源
echo -e "\n2. 测试镜像源可用性..."
test_mirror() {
    local url=$1
    if curl -s -I --connect-timeout 3 "$url" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

AVAILABLE_MIRRORS=()
if test_mirror "https://reg-mirror.qiniu.com"; then
    AVAILABLE_MIRRORS+=("https://reg-mirror.qiniu.com")
    echo "  ✓ 七牛云可用"
fi
if test_mirror "https://hub-mirror.c.163.com"; then
    AVAILABLE_MIRRORS+=("https://hub-mirror.c.163.com")
    echo "  ✓ 网易可用"
fi

# 3. 方案选择
echo -e "\n3. 选择配置方案:"
echo "  A) 移除镜像源配置，使用本地镜像（推荐）"
echo "  B) 使用可用的镜像源（如果有）"
echo "  C) 删除配置文件，让 k3s 使用默认配置"

read -p "请选择 (A/B/C): " -n 1 -r
echo

case $REPLY in
    [Aa])
        echo -e "\n方案 A: 移除镜像源配置，使用 Docker Hub"
        echo "备份现有配置..."
        if [ -f /etc/rancher/k3s/registries.yaml ]; then
            sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.bak
            echo "✓ 已备份到 /etc/rancher/k3s/registries.yaml.bak"
        fi
        
        echo "删除镜像源配置（k3s 将直接使用 Docker Hub）..."
        sudo rm -f /etc/rancher/k3s/registries.yaml
        echo "✓ 配置文件已删除，k3s 将使用 Docker Hub"
        ;;
    [Bb])
        if [ ${#AVAILABLE_MIRRORS[@]} -eq 0 ]; then
            echo "✗ 没有可用的镜像源，使用方案 A"
            sudo rm -f /etc/rancher/k3s/registries.yaml
        else
            echo -e "\n方案 B: 使用可用镜像源"
            sudo mkdir -p /etc/rancher/k3s
            MIRROR_LIST=""
            for mirror in "${AVAILABLE_MIRRORS[@]}"; do
                MIRROR_LIST="${MIRROR_LIST}      - \"${mirror}\"\n"
            done
            sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
${MIRROR_LIST}  registry-1.docker.io:
    endpoint:
${MIRROR_LIST}EOF
            echo "✓ 已配置可用镜像源: ${AVAILABLE_MIRRORS[*]}"
        fi
        ;;
    [Cc])
        echo -e "\n方案 C: 删除配置文件"
        if [ -f /etc/rancher/k3s/registries.yaml ]; then
            sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.bak
            sudo rm -f /etc/rancher/k3s/registries.yaml
            echo "✓ 配置文件已删除（已备份）"
        else
            echo "配置文件不存在"
        fi
        ;;
    *)
        echo "无效选择，使用方案 A"
        sudo rm -f /etc/rancher/k3s/registries.yaml
        ;;
esac

# 4. 确保本地镜像已 tag
echo -e "\n4. 确保本地镜像已 tag..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if ! crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "Tag 本地 pause 镜像..."
    if sudo ctr -n k8s.io images tag \
        registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
        rancher/mirrored-pause:3.6 2>&1; then
        echo "✓ Tag 成功"
    else
        echo "⚠️  Tag 失败，但继续..."
    fi
else
    echo "✓ 本地已有 rancher/mirrored-pause:3.6 镜像"
fi

# 5. 重启 k3s
echo -e "\n5. 重启 k3s（使配置生效）..."
read -p "是否现在重启 k3s? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart k3s
    echo "等待 k3s 就绪..."
    sleep 15
    
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✓ k3s 已就绪"
    else
        echo "⚠️  k3s 可能还在启动中"
    fi
else
    echo "跳过重启，请稍后手动重启: sudo systemctl restart k3s"
fi

# 6. 删除 Pod 重新创建
echo -e "\n6. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除"

echo -e "\n观察 Pod 状态（30 秒）:"
timeout 30 kubectl get pods -n kubevirt -w 2>/dev/null || kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 仍然无法启动，检查："
echo "  1. 镜像是否存在: crictl images | grep pause"
echo "  2. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
echo "  3. k3s 日志: sudo journalctl -u k3s -n 50 | grep -i pause"

