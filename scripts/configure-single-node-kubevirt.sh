#!/bin/bash

# 配置单节点环境以允许创建 VM

echo "=== 配置单节点环境以允许创建 VM ==="

# 1. 检查节点信息
echo -e "\n1. 检查节点信息..."
kubectl get nodes -o wide

# 2. 检查节点标签
echo -e "\n2. 检查节点标签..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "节点名称: $NODE_NAME"
echo ""
echo "当前标签:"
kubectl get node "$NODE_NAME" --show-labels

# 3. 检查节点污点（Taints）
echo -e "\n3. 检查节点污点..."
echo "当前污点:"
kubectl describe node "$NODE_NAME" | grep -A 5 "Taints:" || echo "  无污点"

# 4. 添加必要的标签
echo -e "\n4. 添加必要的标签..."
echo "添加 kubevirt.io/schedulable=true 标签..."
kubectl label node "$NODE_NAME" kubevirt.io/schedulable=true --overwrite
echo "✓ 已添加标签"

# 5. 移除控制平面污点（如果是控制平面节点）
echo -e "\n5. 检查并移除控制平面污点..."
TAINTS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null)
if echo "$TAINTS" | grep -q "node-role.kubernetes.io/control-plane\|node-role.kubernetes.io/master"; then
    echo "⚠️  发现控制平面污点，移除中..."
    kubectl taint node "$NODE_NAME" node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
    kubectl taint node "$NODE_NAME" node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
    echo "✓ 已移除控制平面污点"
else
    echo "✓ 无控制平面污点"
fi

# 6. 检查 KubeVirt 配置
echo -e "\n6. 检查 KubeVirt 配置..."
if kubectl get kubevirt -n kubevirt kubevirt 2>/dev/null | grep -q kubevirt; then
    echo "KubeVirt CR 存在，检查配置..."
    kubectl get kubevirt -n kubevirt kubevirt -o yaml | grep -A 10 "nodePlacement:" || echo "  未配置 nodePlacement"
    
    # 检查是否需要更新配置
    NODE_PLACEMENT=$(kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.spec.workloadUpdateStrategy}' 2>/dev/null)
    if [ -z "$NODE_PLACEMENT" ]; then
        echo "KubeVirt 配置正常，允许在所有节点上调度"
    fi
else
    echo "⚠️  KubeVirt CR 不存在，需要先创建"
    echo "运行: ./scripts/create-kubevirt-cr.sh"
fi

# 7. 检查节点资源
echo -e "\n7. 检查节点资源..."
echo "CPU 和内存:"
kubectl describe node "$NODE_NAME" | grep -A 5 "Allocated resources:"

# 8. 检查 virt-handler
echo -e "\n8. 检查 virt-handler..."
if kubectl get daemonset -n kubevirt virt-handler 2>/dev/null | grep -q virt-handler; then
    echo "virt-handler DaemonSet 状态:"
    kubectl get daemonset -n kubevirt virt-handler
    echo ""
    echo "virt-handler Pods:"
    kubectl get pods -n kubevirt -l kubevirt.io=virt-handler -o wide
else
    echo "⚠️  virt-handler DaemonSet 不存在（KubeVirt 可能还未完全部署）"
fi

# 9. 更新 KubeVirt CR（如果需要）
echo -e "\n9. 更新 KubeVirt CR（允许在控制平面节点调度）..."
if kubectl get kubevirt -n kubevirt kubevirt 2>/dev/null | grep -q kubevirt; then
    # 检查是否已有 nodePlacement 配置
    HAS_NODE_PLACEMENT=$(kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.spec.workloadUpdateStrategy}' 2>/dev/null)
    
    if [ -z "$HAS_NODE_PLACEMENT" ]; then
        echo "更新 KubeVirt CR，添加 tolerations 以允许在控制平面节点调度..."
        kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{
          "spec": {
            "workloadUpdateStrategy": {},
            "configuration": {
              "developerConfiguration": {
                "useEmulation": true
              }
            }
          }
        }'
        echo "✓ 已更新 KubeVirt CR"
    else
        echo "KubeVirt CR 已有配置，跳过更新"
    fi
fi

# 10. 验证配置
echo -e "\n10. 验证配置..."
echo "节点标签:"
kubectl get node "$NODE_NAME" --show-labels | grep -E "NAME|kubevirt"

echo ""
echo "节点污点:"
kubectl describe node "$NODE_NAME" | grep "Taints:" || echo "  无污点"

echo ""
echo "节点资源:"
kubectl top node "$NODE_NAME" 2>/dev/null || echo "  metrics-server 未安装，无法查看资源使用"

# 11. 总结
echo -e "\n=== 配置完成 ==="
echo ""
echo "已完成的配置:"
echo "  ✓ 添加 kubevirt.io/schedulable=true 标签"
echo "  ✓ 移除控制平面污点（如果存在）"
echo ""
echo "现在可以尝试创建 VM:"
echo "  kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"
echo ""
echo "检查 VM 调度:"
echo "  kubectl get vm -o wide"
echo "  kubectl get vmi -o wide"
echo "  kubectl get pods -o wide | grep virt-launcher"
echo ""
echo "如果 VM 仍然无法调度，检查:"
echo "  1. 节点资源是否充足: kubectl describe node"
echo "  2. Pod 事件: kubectl get events --sort-by='.lastTimestamp' | tail -20"
echo "  3. virt-handler 是否运行: kubectl get pods -n kubevirt -l kubevirt.io=virt-handler"

echo ""
echo "=== 完成 ==="

