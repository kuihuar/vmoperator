#!/bin/bash

# 修复 Longhorn iscsi 问题

set -e

echo "=== 修复 Longhorn iscsi 问题 ==="
echo ""

# 1. 检查当前状态
echo "1. 检查 Longhorn Manager 状态..."
kubectl get pods -n longhorn-system -l app=longhorn-manager
echo ""

# 2. 获取节点列表
echo "2. 获取节点列表..."
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
echo "节点: $NODES"
echo ""

# 3. 提供安装说明
echo "3. 安装 open-iscsi..."
echo ""
echo "需要在每个节点上安装 open-iscsi:"
echo ""
for node in $NODES; do
    echo "节点: $node"
    echo "  方法 1: SSH 到节点并运行安装脚本"
    echo "    ssh $node"
    echo "    ./scripts/install-open-iscsi.sh"
    echo ""
    echo "  方法 2: 使用 kubectl exec（如果节点上有 Pod）"
    echo "    kubectl debug node/$node -it --image=ubuntu:latest -- /bin/bash"
    echo "    apt-get update && apt-get install -y open-iscsi"
    echo ""
done

# 4. 检查是否已安装
echo "4. 检查节点上的 iscsiadm..."
for node in $NODES; do
    echo "检查节点: $node"
    # 尝试在节点上执行命令（需要 DaemonSet 或 Pod）
    if kubectl get daemonset -n longhorn-system longhorn-manager &>/dev/null; then
        # 尝试通过 longhorn-manager Pod 检查
        MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --field-selector spec.nodeName=$node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$MANAGER_POD" ]; then
            echo "  通过 Pod $MANAGER_POD 检查..."
            if kubectl exec -n longhorn-system $MANAGER_POD -- nsenter --mount=/host/proc/1/ns/mnt -- iscsiadm --version &>/dev/null; then
                echo "  ✓ iscsiadm 已安装"
            else
                echo "  ❌ iscsiadm 未安装"
            fi
        fi
    fi
    echo ""
done

# 5. 提供快速修复步骤
echo "5. 快速修复步骤:"
echo ""
echo "步骤 1: 在每个节点上安装 open-iscsi"
echo "  Ubuntu/Debian:"
echo "    sudo apt-get update"
echo "    sudo apt-get install -y open-iscsi"
echo ""
echo "  CentOS/RHEL:"
echo "    sudo yum install -y iscsi-initiator-utils"
echo ""
echo "步骤 2: 重启 longhorn-manager Pods"
echo "  kubectl delete pod -n longhorn-system -l app=longhorn-manager"
echo ""
echo "步骤 3: 等待 Pods 重新创建并验证"
echo "  kubectl get pods -n longhorn-system -w"
echo ""

echo "=== 完成 ==="

