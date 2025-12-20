#!/bin/bash

# KubeVirt 安装脚本

set -e

echo "=== 安装 KubeVirt ==="

# 1. 获取 KubeVirt 版本
echo -e "\n1. 获取 KubeVirt 版本..."
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | \
  grep tag_name | grep -v -- '-rc' | head -1 | \
  awk -F': ' '{print $2}' | sed 's/,//' | xargs)

if [ -z "$KUBEVIRT_VERSION" ]; then
    echo "错误: 无法获取 KubeVirt 版本，使用默认版本 v1.2.0"
    export KUBEVIRT_VERSION=v1.2.0
fi

echo "KubeVirt 版本: $KUBEVIRT_VERSION"

# 2. 检查是否已安装
echo -e "\n2. 检查现有安装..."
if kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1; then
    echo "⚠️  KubeVirt Operator 似乎已安装"
    read -p "是否继续重新安装? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消安装"
        exit 0
    fi
    echo "删除现有安装..."
    kubectl delete kubevirt -n kubevirt kubevirt 2>/dev/null || true
    kubectl delete deployment -n kubevirt virt-operator 2>/dev/null || true
    sleep 5
fi

# 3. 安装 KubeVirt Operator
echo -e "\n3. 安装 KubeVirt Operator..."
echo "下载: https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

echo -e "\n等待 KubeVirt Operator 就绪..."
if kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s 2>/dev/null; then
    echo "✓ KubeVirt Operator 已就绪"
else
    echo "✗ KubeVirt Operator 启动超时，请检查日志:"
    echo "  kubectl logs -n kubevirt deployment/virt-operator"
    echo "  kubectl describe pod -n kubevirt -l app=virt-operator"
    echo ""
    echo "继续安装 KubeVirt CR（Operator 可能仍在启动中）..."
fi

# 4. 安装 KubeVirt CR
echo -e "\n4. 安装 KubeVirt CR..."
echo "下载: https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

echo -e "\n等待 KubeVirt 就绪（这可能需要几分钟）..."
if kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s 2>/dev/null; then
    echo "✓ KubeVirt 已就绪"
else
    echo "⚠️  KubeVirt 启动超时，但可能仍在初始化中"
    echo "检查状态: kubectl get kubevirt -n kubevirt"
    echo "检查 Pods: kubectl get pods -n kubevirt"
fi

# 5. 配置 KubeVirt（k3s 环境通常需要）
echo -e "\n5. 配置 KubeVirt（k3s 环境）..."
echo "在 k3s 环境中，通常需要启用软件模拟（如果硬件不支持 KVM）"
read -p "是否启用 useEmulation? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "启用 useEmulation..."
    kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
    echo "✓ useEmulation 已启用"
fi

# 6. 验证安装
echo -e "\n6. 验证安装..."

# 检查 Operator Pods
echo -e "\nKubeVirt Operator Pods:"
kubectl get pods -n kubevirt -l app=virt-operator

# 检查其他组件
echo -e "\nKubeVirt 组件 Pods:"
kubectl get pods -n kubevirt

# 检查 CRD
echo -e "\nKubeVirt CRDs:"
kubectl get crd | grep kubevirt.io

# 检查 KubeVirt CR
echo -e "\nKubeVirt CR 状态:"
kubectl get kubevirt -n kubevirt

# 检查 API 资源
echo -e "\nKubeVirt API 资源:"
if kubectl api-resources | grep -q virtualmachines; then
    echo "✓ VirtualMachine API 已注册"
    kubectl api-resources | grep virtualmachine
else
    echo "⚠️  VirtualMachine API 未注册（可能需要等待 API Server 刷新）"
fi

# 检查节点 label
echo -e "\n7. 检查节点 label（KubeVirt 需要）:"
if kubectl get nodes --show-labels | grep -q kubevirt.io/schedulable; then
    echo "✓ 节点已标记为可调度"
    kubectl get nodes --show-labels | grep kubevirt.io/schedulable
else
    echo "⚠️  节点未标记为可调度"
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    echo "添加 label: kubectl label node $NODE_NAME kubevirt.io/schedulable=true"
    read -p "是否现在添加? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        kubectl label node $NODE_NAME kubevirt.io/schedulable=true
        echo "✓ Label 已添加"
    fi
fi

echo -e "\n=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 运行检查脚本: ./scripts/check-kubevirt-installation.sh"
echo "  2. 安装 CDI: ./scripts/install-cdi.sh"
echo "  3. 运行 Controller: make run"
echo "  4. 创建 Wukong 资源: kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"

