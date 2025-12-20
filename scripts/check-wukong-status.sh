#!/bin/bash

# 检查 Wukong 和 VM 状态

echo "=== 检查 Wukong 和 VM 状态 ==="

# 1. 检查 Wukong 资源
echo -e "\n1. 检查 Wukong 资源..."
if kubectl get wukong 2>/dev/null | grep -q .; then
    echo "✓ 找到 Wukong 资源:"
    kubectl get wukong
    echo ""
    
    # 检查每个 Wukong 的详情
    for wukong in $(kubectl get wukong -o jsonpath='{.items[*].metadata.name}'); do
        echo "--- Wukong: $wukong ---"
        kubectl get wukong "$wukong" -o yaml | grep -A 30 "status:" | head -35
        echo ""
    done
else
    echo "⚠️  未找到 Wukong 资源"
    echo ""
    echo "需要创建 Wukong 资源，运行:"
    echo "  kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"
    echo ""
    echo "或者检查示例文件:"
    echo "  ls -la config/samples/vm_v1alpha1_wukong*.yaml"
fi

# 2. 检查 VM 资源
echo -e "\n2. 检查 VM 资源..."
if kubectl get vm 2>/dev/null | grep -q .; then
    echo "✓ 找到 VM 资源:"
    kubectl get vm
    echo ""
    echo "VM 详情:"
    for vm in $(kubectl get vm -o jsonpath='{.items[*].metadata.name}'); do
        echo "--- VM: $vm ---"
        kubectl get vm "$vm" -o yaml | grep -A 20 "status:" | head -25
        echo ""
    done
else
    echo "⚠️  未找到 VM 资源"
    echo "如果 Wukong 资源存在，可能是 controller 还未创建 VM"
fi

# 3. 检查 VMI 资源
echo -e "\n3. 检查 VMI 资源..."
if kubectl get vmi 2>/dev/null | grep -q .; then
    echo "✓ 找到 VMI 资源:"
    kubectl get vmi
else
    echo "⚠️  未找到 VMI 资源（VM 可能还未启动）"
fi

# 4. 检查 Controller 是否运行
echo -e "\n4. 检查 Controller 是否运行..."
if kubectl get pods -A | grep -E "novasphere|wukong" | grep -v "Completed"; then
    echo "Controller Pods:"
    kubectl get pods -A | grep -E "novasphere|wukong" | grep -v "Completed"
    echo ""
    echo "检查 Controller 日志:"
    CONTROLLER_POD=$(kubectl get pods -A -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="novasphere")].metadata.name}' 2>/dev/null | awk '{print $1}')
    if [ -n "$CONTROLLER_POD" ]; then
        NAMESPACE=$(kubectl get pods -A -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="novasphere")].metadata.namespace}' 2>/dev/null | awk '{print $1}')
        echo "Controller Pod: $CONTROLLER_POD (namespace: $NAMESPACE)"
        kubectl logs -n "$NAMESPACE" "$CONTROLLER_POD" --tail=30 | tail -20
    else
        echo "⚠️  未找到 Controller Pod（可能使用 make run 在本地运行）"
        echo "如果使用 make run，检查运行 make run 的终端"
    fi
else
    echo "⚠️  未找到 Controller Pod"
    echo "检查是否使用 make run 在本地运行:"
    echo "  如果是，检查运行 make run 的终端"
    echo "  如果不是，需要部署 controller:"
    echo "    make deploy"
fi

# 5. 检查事件
echo -e "\n5. 检查最新事件..."
echo "default namespace 事件:"
kubectl get events -n default --sort-by='.lastTimestamp' 2>/dev/null | tail -10

# 6. 检查 CRD 是否安装
echo -e "\n6. 检查 CRD 是否安装..."
if kubectl get crd wukongs.vm.novasphere.dev 2>/dev/null | grep -q wukong; then
    echo "✓ Wukong CRD 已安装"
else
    echo "❌ Wukong CRD 未安装"
    echo "运行: make install"
fi

if kubectl get crd virtualmachines.kubevirt.io 2>/dev/null | grep -q virtualmachine; then
    echo "✓ VirtualMachine CRD 已安装"
else
    echo "❌ VirtualMachine CRD 未安装（KubeVirt 可能未完全部署）"
fi

# 7. 检查示例文件
echo -e "\n7. 检查示例文件..."
if [ -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml ]; then
    echo "✓ 示例文件存在: config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"
    echo "文件内容预览:"
    head -20 config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
else
    echo "⚠️  示例文件不存在"
    echo "检查其他示例文件:"
    ls -la config/samples/vm_v1alpha1_wukong*.yaml 2>/dev/null || echo "  未找到示例文件"
fi

# 8. 总结和建议
echo -e "\n=== 总结和建议 ==="
echo ""

if kubectl get wukong 2>/dev/null | grep -q .; then
    echo "✓ Wukong 资源存在"
    if kubectl get vm 2>/dev/null | grep -q .; then
        echo "✓ VM 资源存在"
        echo ""
        echo "检查 VM 状态:"
        kubectl get vm -o wide
    else
        echo "⚠️  VM 资源不存在"
        echo ""
        echo "可能的原因："
        echo "  1. Controller 还未处理 Wukong 资源"
        echo "  2. Controller 运行出错"
        echo "  3. Wukong 资源配置有问题"
        echo ""
        echo "检查："
        echo "  1. Controller 日志（见上方）"
        echo "  2. Wukong 状态: kubectl get wukong -o yaml"
        echo "  3. 事件: kubectl get events --sort-by='.lastTimestamp' | tail -20"
    fi
else
    echo "⚠️  Wukong 资源不存在"
    echo ""
    echo "下一步："
    echo "  1. 确保 CRD 已安装: make install"
    echo "  2. 创建 Wukong 资源: kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"
    echo "  3. 确保 Controller 正在运行（make run 或 make deploy）"
fi

echo ""
echo "=== 检查完成 ==="

