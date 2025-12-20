#!/bin/bash

# 诊断为什么 Wukong 没有创建 VM

echo "=== 诊断 Wukong 为什么没有创建 VM ==="

# 1. 检查 Wukong 资源
echo -e "\n1. 检查 Wukong 资源..."
WUKONG_NAME=$(kubectl get wukong -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$WUKONG_NAME" ]; then
    echo "Wukong 名称: $WUKONG_NAME"
    echo ""
    echo "Wukong 状态:"
    kubectl get wukong "$WUKONG_NAME" -o yaml | grep -A 50 "status:" | head -60
else
    echo "❌ 未找到 Wukong 资源"
    exit 1
fi

# 2. 检查 Controller 是否运行
echo -e "\n2. 检查 Controller 是否运行..."
if pgrep -f "novasphere.*manager" > /dev/null 2>&1; then
    echo "✓ Controller 进程正在运行（make run）"
    echo "进程信息:"
    ps aux | grep "novasphere.*manager" | grep -v grep
else
    echo "⚠️  Controller 进程未运行（make run）"
    echo "检查是否部署为 Pod:"
    kubectl get pods -A | grep -E "novasphere|wukong" | grep -v "Completed" || echo "  未找到 Controller Pod"
fi

# 3. 检查 Controller 日志（如果可能）
echo -e "\n3. 检查 Controller 日志..."
if pgrep -f "novasphere.*manager" > /dev/null 2>&1; then
    echo "⚠️  Controller 在本地运行（make run），请检查运行 make run 的终端"
    echo "或者查看日志文件（如果有）"
else
    CONTROLLER_POD=$(kubectl get pods -A -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="novasphere")].metadata.name}' 2>/dev/null | awk '{print $1}')
    if [ -n "$CONTROLLER_POD" ]; then
        NAMESPACE=$(kubectl get pods -A -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="novasphere")].metadata.namespace}' 2>/dev/null | awk '{print $1}')
        echo "Controller Pod: $CONTROLLER_POD (namespace: $NAMESPACE)"
        echo "最近 50 行日志:"
        kubectl logs -n "$NAMESPACE" "$CONTROLLER_POD" --tail=50 | tail -30
    else
        echo "⚠️  未找到 Controller Pod"
    fi
fi

# 4. 检查事件
echo -e "\n4. 检查与 Wukong 相关的事件..."
kubectl get events --field-selector involvedObject.name="$WUKONG_NAME" --sort-by='.lastTimestamp' 2>/dev/null | tail -20

# 5. 检查 PVC 状态
echo -e "\n5. 检查 PVC 状态..."
kubectl get pvc | grep -E "NAME|$WUKONG_NAME"
echo ""
PVC_NAME=$(kubectl get pvc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | grep "$WUKONG_NAME" | head -1)
if [ -n "$PVC_NAME" ]; then
    echo "PVC 详情: $PVC_NAME"
    kubectl describe pvc "$PVC_NAME" | grep -A 10 "Events:" | head -15
fi

# 6. 检查 DataVolume 状态
echo -e "\n6. 检查 DataVolume 状态..."
kubectl get datavolume 2>/dev/null | grep -E "NAME|$WUKONG_NAME" || echo "  未找到 DataVolume"

# 7. 检查 Wukong 的 Conditions
echo -e "\n7. 检查 Wukong 的 Conditions..."
kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.status.conditions[*]}' 2>/dev/null | jq -r '.' 2>/dev/null || kubectl get wukong "$WUKONG_NAME" -o yaml | grep -A 10 "conditions:" | head -15

# 8. 检查是否有错误
echo -e "\n8. 检查是否有错误..."
echo "检查 Wukong 是否有错误状态:"
kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.status.phase}' 2>/dev/null
echo ""

# 9. 检查 Controller RBAC
echo -e "\n9. 检查 Controller RBAC..."
echo "检查 ServiceAccount:"
kubectl get sa -A | grep -E "novasphere|wukong" || echo "  未找到（如果使用 make run，可能不需要）"

# 10. 建议
echo -e "\n=== 诊断总结 ==="
echo ""

if kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Error"; then
    echo "⚠️  Wukong 状态为 Error"
    echo "检查 Wukong 详情: kubectl get wukong $WUKONG_NAME -o yaml"
elif [ -z "$(kubectl get vm 2>/dev/null | grep -v NAME)" ]; then
    echo "⚠️  VM 资源未创建"
    echo ""
    echo "可能的原因："
    echo "  1. Controller 未运行"
    echo "  2. Controller 处理 Wukong 时出错"
    echo "  3. Wukong 配置有问题"
    echo "  4. 依赖资源未就绪（如 PVC）"
    echo ""
    echo "下一步："
    echo "  1. 确保 Controller 正在运行: make run"
    echo "  2. 检查 Controller 日志（见上方）"
    echo "  3. 检查 Wukong 状态: kubectl get wukong $WUKONG_NAME -o yaml"
    echo "  4. 检查事件: kubectl get events --sort-by='.lastTimestamp' | tail -30"
fi

echo ""
echo "=== 诊断完成 ==="

