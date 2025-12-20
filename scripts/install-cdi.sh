#!/bin/bash

# CDI 安装脚本

set -e

echo "=== 安装 CDI (Containerized Data Importer) ==="

# 1. 获取 CDI 版本
echo -e "\n1. 获取 CDI 版本..."
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | \
  grep tag_name | grep -v -- '-rc' | head -1 | \
  awk -F': ' '{print $2}' | sed 's/,//' | xargs)

if [ -z "$CDI_VERSION" ]; then
    echo "错误: 无法获取 CDI 版本，使用默认版本 v1.62.0"
    export CDI_VERSION=v1.62.0
fi

echo "CDI 版本: $CDI_VERSION"

# 2. 检查是否已安装
echo -e "\n2. 检查现有安装..."
if kubectl get crd datavolumes.cdi.kubevirt.io > /dev/null 2>&1; then
    echo "⚠️  CDI 似乎已安装，但可能不完整"
    read -p "是否继续重新安装? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消安装"
        exit 0
    fi
fi

# 3. 安装 CDI Operator
echo -e "\n3. 安装 CDI Operator..."
echo "下载: https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

echo -e "\n等待 CDI Operator 就绪..."
if kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s 2>/dev/null; then
    echo "✓ CDI Operator 已就绪"
else
    echo "✗ CDI Operator 启动超时，请检查日志:"
    echo "  kubectl logs -n cdi deployment/cdi-operator"
    echo "  kubectl describe pod -n cdi -l app=cdi-operator"
    exit 1
fi

# 4. 安装 CDI CR
echo -e "\n4. 安装 CDI CR..."
echo "下载: https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

echo -e "\n等待 CDI 就绪（这可能需要几分钟）..."
if kubectl wait -n cdi cdi cdi --for condition=Available --timeout=600s 2>/dev/null; then
    echo "✓ CDI 已就绪"
else
    echo "⚠️  CDI 启动超时，但可能仍在初始化中"
    echo "检查状态: kubectl get cdi -n cdi"
    echo "检查 Pods: kubectl get pods -n cdi"
fi

# 5. 验证安装
echo -e "\n5. 验证安装..."

# 检查 CRD
if kubectl get crd datavolumes.cdi.kubevirt.io > /dev/null 2>&1; then
    echo "✓ DataVolume CRD 已安装"
else
    echo "✗ DataVolume CRD 未找到"
    echo "  等待 30 秒后重试..."
    sleep 30
    if kubectl get crd datavolumes.cdi.kubevirt.io > /dev/null 2>&1; then
        echo "✓ DataVolume CRD 已安装（延迟注册）"
    else
        echo "✗ DataVolume CRD 仍未找到，请检查 Operator 日志"
        exit 1
    fi
fi

# 检查 Pods
echo -e "\nCDI Pods 状态:"
kubectl get pods -n cdi

# 检查 CDI CR
echo -e "\nCDI CR 状态:"
kubectl get cdi -n cdi

# 检查 API 资源
echo -e "\nDataVolume API 资源:"
if kubectl api-resources | grep -q datavolumes; then
    echo "✓ DataVolume API 已注册"
    kubectl api-resources | grep datavolumes
else
    echo "⚠️  DataVolume API 未注册（可能需要等待 API Server 刷新）"
    echo "   等待 10 秒后重试..."
    sleep 10
    if kubectl api-resources | grep -q datavolumes; then
        echo "✓ DataVolume API 已注册"
        kubectl api-resources | grep datavolumes
    else
        echo "⚠️  DataVolume API 仍未注册，但 CRD 已存在，应该可以正常使用"
    fi
fi

echo -e "\n=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 运行检查脚本: ./scripts/check-cdi-installation.sh"
echo "  2. 重新运行 Controller: make run"
echo "  3. 创建 Wukong 资源: kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"

