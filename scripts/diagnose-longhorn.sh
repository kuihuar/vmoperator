#!/bin/bash

# 诊断 Longhorn 安装问题

echo "=== 诊断 Longhorn 问题 ==="

# 1. 检查 Pod 状态
echo "1. 检查 Pod 状态..."
kubectl get pods -n longhorn-system
echo ""

# 2. 检查 longhorn-manager 日志
echo "2. 检查 longhorn-manager 日志..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    echo "Manager Pod: $MANAGER_POD"
    echo "最近的日志:"
    kubectl logs -n longhorn-system "$MANAGER_POD" --tail=50 2>&1 | head -30
else
    echo "未找到 longhorn-manager Pod"
fi
echo ""

# 3. 检查 longhorn-driver-deployer 日志
echo "3. 检查 longhorn-driver-deployer 日志..."
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYER_POD" ]; then
    echo "Driver Deployer Pod: $DEPLOYER_POD"
    echo "Pod 详情:"
    kubectl describe pod -n longhorn-system "$DEPLOYER_POD" | grep -A 20 "Events:"
    echo ""
    echo "Init Container 日志:"
    kubectl logs -n longhorn-system "$DEPLOYER_POD" -c wait-longhorn-manager --tail=50 2>&1 || echo "无法获取 Init Container 日志"
else
    echo "未找到 longhorn-driver-deployer Pod"
fi
echo ""

# 4. 检查节点资源
echo "4. 检查节点资源..."
kubectl top nodes 2>/dev/null || echo "无法获取节点资源使用情况（需要 metrics-server）"
kubectl describe nodes | grep -A 10 "Allocated resources:" || echo "无法获取节点资源详情"
echo ""

# 5. 检查节点标签
echo "5. 检查节点标签..."
kubectl get nodes --show-labels | grep -E "NAME|longhorn"
echo ""

# 6. 检查 Longhorn 配置
echo "6. 检查 Longhorn 配置..."
kubectl get configmap -n longhorn-system 2>/dev/null | head -5
echo ""

# 7. 检查事件
echo "7. 检查最近的事件..."
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | tail -20
echo ""

# 8. 常见问题检查
echo "8. 常见问题检查..."
echo ""

# 检查节点是否可调度
echo "检查节点调度状态:"
kubectl get nodes -o wide
echo ""

# 检查存储路径
echo "检查 Longhorn 存储路径配置:"
kubectl get setting -n longhorn-system default-data-path -o yaml 2>/dev/null || echo "无法获取存储路径配置"
echo ""

# 检查节点磁盘空间
echo "检查节点磁盘空间（需要 SSH 访问节点）:"
echo "请在节点上执行: df -h"
echo ""

echo "=== 诊断完成 ==="
echo ""
echo "常见问题和解决方案:"
echo "  1. 节点资源不足: 检查节点 CPU/内存"
echo "  2. 存储路径问题: 检查节点磁盘空间和权限"
echo "  3. 网络问题: 检查节点网络连接"
echo "  4. 权限问题: 检查 ServiceAccount 权限"
echo ""
echo "查看详细日志:"
echo "  kubectl logs -n longhorn-system <pod-name>"
echo "  kubectl describe pod -n longhorn-system <pod-name>"

