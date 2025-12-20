#!/bin/bash

# 修复 KubeVirt 安装问题

echo "=== 修复 KubeVirt 安装 ==="

# 1. 检查当前状态
echo -e "\n1. 检查当前安装状态..."

# 检查 Deployment
if kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1; then
    echo "   ✓ virt-operator Deployment 存在"
    kubectl get deployment -n kubevirt virt-operator
    echo ""
    
    # 检查 Pods
    PODS=$(kubectl get pods -n kubevirt -l app=virt-operator --no-headers 2>/dev/null | wc -l)
    if [ "$PODS" -gt 0 ]; then
        echo "   Pods 状态:"
        kubectl get pods -n kubevirt -l app=virt-operator
    else
        echo "   ⚠️  没有运行中的 Pods"
    fi
else
    echo "   ✗ virt-operator Deployment 不存在"
fi

# 检查 KubeVirt CR
if kubectl get kubevirt -n kubevirt kubevirt > /dev/null 2>&1; then
    echo -e "\n   ✓ KubeVirt CR 已创建"
    kubectl get kubevirt -n kubevirt kubevirt
else
    echo -e "\n   ✗ KubeVirt CR 未创建"
fi

# 2. 决定操作
echo -e "\n2. 选择操作:"
echo "   资源已存在，可以选择："
echo "   A) 继续安装 KubeVirt CR（如果 Operator 已就绪）"
echo "   B) 清理后重新安装（如果 Operator 有问题）"
echo "   C) 仅检查状态"

read -p "请选择 (A/B/C): " -n 1 -r
echo

case $REPLY in
    [Aa])
        echo -e "\n=== 继续安装 KubeVirt CR ==="
        
        # 检查 Operator 是否就绪
        if kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=10s 2>/dev/null; then
            echo "✓ Operator 已就绪，继续安装 CR..."
            
            # 检查 CR 是否已存在
            if kubectl get kubevirt -n kubevirt kubevirt > /dev/null 2>&1; then
                echo "⚠️  KubeVirt CR 已存在，跳过安装"
            else
                # 获取版本
                export KUBEVIRT_VERSION=$(kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://' || echo "v1.2.0")
                echo "检测到版本: $KUBEVIRT_VERSION"
                
                # 尝试安装 CR
                CR_URL="https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
                echo "下载 CR: $CR_URL"
                
                if kubectl create -f "$CR_URL" 2>/dev/null; then
                    echo "✓ CR 安装成功"
                else
                    # 尝试镜像源
                    GH_PROXY_URL="https://ghproxy.com/${CR_URL}"
                    echo "尝试镜像源: $GH_PROXY_URL"
                    if kubectl create -f "$GH_PROXY_URL" 2>/dev/null; then
                        echo "✓ CR 安装成功（使用镜像源）"
                    else
                        echo "✗ CR 安装失败，请手动下载并安装"
                        echo "   URL: $CR_URL"
                    fi
                fi
            fi
        else
            echo "✗ Operator 未就绪，请先修复 Operator"
            echo "   运行: kubectl get pods -n kubevirt -l app=virt-operator"
            exit 1
        fi
        ;;
    [Bb])
        echo -e "\n=== 清理并重新安装 ==="
        read -p "确认删除现有 KubeVirt 安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "取消操作"
            exit 0
        fi
        
        echo "删除 KubeVirt CR..."
        kubectl delete kubevirt -n kubevirt kubevirt 2>/dev/null || true
        
        echo "删除 Operator Deployment..."
        kubectl delete deployment -n kubevirt virt-operator 2>/dev/null || true
        
        echo "等待资源清理..."
        sleep 10
        
        echo "重新安装..."
        ./scripts/install-kubevirt.sh
        ;;
    [Cc])
        echo -e "\n=== 当前状态 ==="
        ./scripts/check-kubevirt-installation.sh
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

# 3. 最终验证
echo -e "\n=== 最终状态 ==="
kubectl get pods -n kubevirt
kubectl get kubevirt -n kubevirt 2>/dev/null || echo "KubeVirt CR 未创建"

