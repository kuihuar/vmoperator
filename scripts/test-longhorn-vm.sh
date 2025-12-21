#!/bin/bash

# 测试使用 Longhorn 创建虚拟机

set -e

echo "=== 测试使用 Longhorn 创建虚拟机 ==="
echo ""

# 1. 检查 Longhorn StorageClass
echo "1. 检查 Longhorn StorageClass..."
if ! kubectl get storageclass longhorn &>/dev/null; then
    echo "❌ longhorn StorageClass 不存在"
    echo "请先安装 Longhorn: ./scripts/setup-longhorn.sh"
    exit 1
fi

echo "✓ longhorn StorageClass 存在"
ALLOW_EXPANSION=$(kubectl get storageclass longhorn -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
if [ "$ALLOW_EXPANSION" = "true" ]; then
    echo "✓ 支持卷扩展"
fi
echo ""

# 2. 检查 Wukong CRD
echo "2. 检查 Wukong CRD..."
if ! kubectl get crd wukongs.vm.novasphere.dev &>/dev/null; then
    echo "❌ Wukong CRD 不存在"
    echo "请先安装 CRD: make install"
    exit 1
fi

echo "✓ Wukong CRD 存在"
echo ""

# 3. 检查 Controller 是否运行
echo "3. 检查 Controller 是否运行..."
if kubectl get pods -n novasphere-system -l app.kubernetes.io/name=novasphere --no-headers 2>/dev/null | grep -q "Running"; then
    echo "✓ Controller 正在运行"
else
    echo "⚠️  Controller 未运行"
    echo "请启动 Controller: make run"
    echo "或部署 Controller: make deploy"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# 4. 创建测试 Wukong
echo "4. 创建测试 Wukong..."
WUKONG_NAME="ubuntu-longhorn-test"

# 检查是否已存在
if kubectl get wukong "$WUKONG_NAME" &>/dev/null; then
    echo "⚠️  Wukong 已存在: $WUKONG_NAME"
    read -p "是否删除并重新创建？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "删除现有 Wukong..."
        kubectl delete wukong "$WUKONG_NAME" --wait=false
        sleep 5
    else
        echo "使用现有 Wukong"
    fi
fi

# 创建新的 Wukong
if ! kubectl get wukong "$WUKONG_NAME" &>/dev/null; then
    echo "创建 Wukong..."
    kubectl apply -f config/samples/vm_v1alpha1_wukong_longhorn_test.yaml
    echo "✓ Wukong 已创建"
else
    echo "使用现有 Wukong"
fi
echo ""

# 5. 等待并监控
echo "5. 等待 Controller 处理..."
echo "监控 Wukong 状态..."
sleep 5

MAX_WAIT=600  # 最多等待 10 分钟
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    WUKONG_STATUS=$(kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    VM_NAME=$(kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.status.vmName}' 2>/dev/null || echo "")
    
    echo "  [$(date +%H:%M:%S)] Wukong 状态: $WUKONG_STATUS"
    
    if [ "$WUKONG_STATUS" = "Running" ]; then
        echo "✓ Wukong 已运行"
        break
    elif [ "$WUKONG_STATUS" = "Error" ]; then
        echo "❌ Wukong 状态为 Error"
        echo "查看详情:"
        kubectl describe wukong "$WUKONG_NAME" | grep -A 20 "Status:"
        exit 1
    fi
    
    # 显示相关资源
    if [ -n "$VM_NAME" ]; then
        VM_STATUS=$(kubectl get vm "$VM_NAME" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "Unknown")
        echo "    VM 状态: $VM_STATUS"
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时"
    echo "检查状态:"
    kubectl get wukong "$WUKONG_NAME"
    kubectl get vm 2>/dev/null | grep "$WUKONG_NAME" || echo "VM 还未创建"
fi
echo ""

# 6. 检查相关资源
echo "6. 检查相关资源..."
echo ""
echo "Wukong 状态:"
kubectl get wukong "$WUKONG_NAME" -o wide
echo ""

echo "VM 状态:"
kubectl get vm 2>/dev/null | grep "$WUKONG_NAME" || echo "VM 还未创建"
echo ""

echo "PVC 状态:"
kubectl get pvc | grep "$WUKONG_NAME" || echo "PVC 还未创建"
echo ""

echo "DataVolume 状态（如果有）:"
kubectl get datavolume 2>/dev/null | grep "$WUKONG_NAME" || echo "DataVolume 还未创建"
echo ""

# 7. 检查 Longhorn 卷
echo "7. 检查 Longhorn 卷..."
if kubectl get volumes.longhorn.io -n longhorn-system 2>/dev/null | grep -q "$WUKONG_NAME"; then
    echo "Longhorn 卷:"
    kubectl get volumes.longhorn.io -n longhorn-system | grep "$WUKONG_NAME"
else
    echo "Longhorn 卷还未创建（可能还在创建中）"
fi
echo ""

# 8. 总结
echo "=== 测试完成 ==="
echo ""
echo "当前状态:"
kubectl get wukong,vm,pvc -l app.kubernetes.io/name=novasphere 2>/dev/null | head -20
echo ""
echo "如果遇到问题，检查:"
echo "  - Controller 日志（如果使用 make run）"
echo "  - Wukong 详情: kubectl describe wukong $WUKONG_NAME"
echo "  - 事件: kubectl get events --sort-by='.lastTimestamp' | tail -20"

