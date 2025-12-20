#!/bin/bash

# 配置 Longhorn 用于单节点环境

set -e

echo "=== 配置 Longhorn 单节点环境 ==="
echo ""

# 1. 检查节点数量
echo "1. 检查节点数量..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "节点数量: $NODE_COUNT"

if [ "$NODE_COUNT" -gt 1 ]; then
    echo "⚠️  检测到多个节点，单节点配置可能不适用"
    read -p "是否继续配置为单节点模式？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "✓ 单节点环境"
fi
echo ""

# 2. 检查 Longhorn 是否就绪
echo "2. 检查 Longhorn 状态..."
if ! kubectl get storageclass longhorn &>/dev/null; then
    echo "❌ Longhorn StorageClass 不存在"
    echo "请先安装 Longhorn: ./scripts/setup-longhorn.sh"
    exit 1
fi

echo "✓ Longhorn StorageClass 存在"
echo ""

# 3. 配置副本数为 1
echo "3. 配置默认副本数为 1..."
if kubectl get setting -n longhorn-system default-replica-count &>/dev/null; then
    CURRENT_VALUE=$(kubectl get setting -n longhorn-system default-replica-count -o jsonpath='{.value}' 2>/dev/null)
    echo "当前副本数: $CURRENT_VALUE"
    
    if [ "$CURRENT_VALUE" != "1" ]; then
        echo "更新副本数为 1..."
        kubectl patch setting -n longhorn-system default-replica-count --type merge -p '{"value":"1"}' 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✓ 副本数已更新为 1"
        else
            echo "⚠️  更新失败，可能需要等待 Longhorn 完全就绪"
            echo "稍后可以手动执行:"
            echo "  kubectl patch setting -n longhorn-system default-replica-count --type merge -p '{\"value\":\"1\"}'"
        fi
    else
        echo "✓ 副本数已经是 1"
    fi
else
    echo "⚠️  Setting 不存在，可能需要等待 Longhorn 完全就绪"
    echo "稍后可以手动执行:"
    echo "  kubectl patch setting -n longhorn-system default-replica-count --type merge -p '{\"value\":\"1\"}'"
fi
echo ""

# 4. 检查节点标签
echo "4. 检查节点标签..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "节点名称: $NODE_NAME"

LABELS=$(kubectl get node "$NODE_NAME" --show-labels | grep -o "node.longhorn.io/[^,]*" || echo "")
if [ -z "$LABELS" ]; then
    echo "ℹ️  节点没有 Longhorn 标签（通常不需要手动添加）"
else
    echo "节点标签: $LABELS"
fi
echo ""

# 5. 检查存储路径
echo "5. 检查存储路径..."
echo "（需要在节点上检查: df -h /var/lib/longhorn）"
echo ""

# 6. 验证配置
echo "6. 验证配置..."
sleep 2

if kubectl get setting -n longhorn-system default-replica-count &>/dev/null; then
    REPLICA_COUNT=$(kubectl get setting -n longhorn-system default-replica-count -o jsonpath='{.value}' 2>/dev/null)
    echo "当前副本数配置: $REPLICA_COUNT"
    
    if [ "$REPLICA_COUNT" = "1" ]; then
        echo "✓ 单节点配置完成"
    else
        echo "⚠️  副本数不是 1，可能需要等待或手动配置"
    fi
else
    echo "⚠️  无法获取副本数配置"
fi
echo ""

# 7. 测试创建 PVC
echo "7. 测试创建 PVC（可选）..."
read -p "是否创建测试 PVC？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "创建测试 PVC..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-single-node-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
    
    echo "等待 PVC 绑定..."
    sleep 5
    
    if kubectl get pvc test-single-node-pvc 2>/dev/null | grep -q "Bound"; then
        echo "✓ 测试 PVC 已绑定（单节点配置成功）"
        echo "清理测试 PVC..."
        kubectl delete pvc test-single-node-pvc
    else
        echo "⚠️  测试 PVC 未绑定，检查状态:"
        kubectl get pvc test-single-node-pvc
    fi
fi

echo ""
echo "=== 配置完成 ==="
echo ""
echo "单节点配置总结:"
echo "  - 副本数: 1（无数据冗余）"
echo "  - 高可用: 否（单节点故障会导致数据不可用）"
echo "  - 适合: 开发/测试环境"
echo ""
echo "可以在 Wukong 中使用:"
echo "  storageClassName: longhorn"
echo ""
echo "注意事项:"
echo "  - 定期备份重要数据"
echo "  - 监控磁盘空间使用"
echo "  - 生产环境建议使用多节点"

