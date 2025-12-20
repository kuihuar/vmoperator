#!/bin/bash

# 快速修复 Multus 在 k3s 中的配置

echo "=== 快速修复 Multus 在 k3s 中的配置 ==="

# 1. 查找 k3s CNI 配置路径
echo -e "\n1. 查找 k3s CNI 配置路径..."
K3S_CNI_PATH=""

# 尝试多个可能的路径
POSSIBLE_PATHS=(
    "/var/lib/rancher/k3s/agent/etc/cni/net.d"
    "/var/lib/rancher/k3s/server/manifests"
    "/etc/cni/net.d"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ] && [ "$(sudo ls -A "$path" 2>/dev/null | wc -l)" -gt 0 ]; then
        K3S_CNI_PATH="$path"
        echo "✓ 找到 k3s CNI 配置路径: $K3S_CNI_PATH"
        echo "配置文件:"
        sudo ls -la "$K3S_CNI_PATH" | head -5
        break
    fi
done

if [ -z "$K3S_CNI_PATH" ]; then
    echo "⚠️  未找到标准的 CNI 配置路径"
    echo "尝试查找其他可能的路径..."
    
    # 查找包含 .conf 或 .conflist 的目录
    FOUND_CONF=$(sudo find /var/lib/rancher/k3s -name "*.conf" -o -name "*.conflist" 2>/dev/null | head -1)
    if [ -n "$FOUND_CONF" ]; then
        K3S_CNI_PATH=$(dirname "$FOUND_CONF")
        echo "✓ 通过配置文件找到路径: $K3S_CNI_PATH"
        echo "配置文件:"
        sudo ls -la "$K3S_CNI_PATH" | head -5
    else
        echo "❌ 无法找到 k3s CNI 配置路径"
        echo ""
        echo "请运行以下命令查找路径:"
        echo "  ./scripts/find-k3s-cni-path.sh"
        echo ""
        echo "或者手动检查:"
        echo "  sudo find /var/lib/rancher/k3s -name '*.conf' -o -name '*.conflist'"
        exit 1
    fi
fi

# 2. 备份 Multus DaemonSet
echo -e "\n2. 备份 Multus DaemonSet..."
kubectl get daemonset -n kube-system kube-multus-ds -o yaml > /tmp/multus-ds-backup-$(date +%Y%m%d-%H%M%S).yaml
echo "✓ 已备份"

# 3. 更新 Multus DaemonSet
echo -e "\n3. 更新 Multus DaemonSet..."
kubectl patch daemonset -n kube-system kube-multus-ds --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes/0/hostPath/path",
    "value": "/var/lib/rancher/k3s/agent/etc/cni/net.d"
  }
]' 2>&1

if [ $? -eq 0 ]; then
    echo "✓ 已更新 CNI 配置路径"
else
    echo "⚠️  更新失败，尝试完整更新..."
    # 如果简单 patch 失败，需要完整更新
    echo "请手动编辑: kubectl edit daemonset -n kube-system kube-multus-ds"
    echo "将 volumes[0].hostPath.path 改为: /var/lib/rancher/k3s/agent/etc/cni/net.d"
    exit 1
fi

# 4. 删除 Pod 触发重启
echo -e "\n4. 删除 Pod 触发重启..."
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo "等待 Pod 重启..."
sleep 15

# 5. 检查状态
echo -e "\n5. 检查状态..."
kubectl get pods -n kube-system -l app=multus

echo ""
echo "检查日志（应该没有错误）:"
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MULTUS_POD" ]; then
    kubectl logs -n kube-system "$MULTUS_POD" --tail=20 | grep -E "error|failed|Found primary CNI|multus-daemon started" || kubectl logs -n kube-system "$MULTUS_POD" --tail=10
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果仍然有错误，检查："
echo "  1. k3s CNI 路径: sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/"
echo "  2. Multus Pod 日志: kubectl logs -n kube-system -l app=multus"
echo "  3. 手动编辑: kubectl edit daemonset -n kube-system kube-multus-ds"

