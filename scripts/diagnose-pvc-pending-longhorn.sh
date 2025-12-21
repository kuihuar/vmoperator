#!/bin/bash

# 诊断 Longhorn PVC Pending 问题

PVC_NAME="${1:-test-pvc}"

echo "=== 诊断 Longhorn PVC Pending 问题 ==="
echo "PVC: $PVC_NAME"
echo ""

# 1. 检查 PVC 状态
echo "1. 检查 PVC 状态..."
kubectl get pvc "$PVC_NAME" -o wide
echo ""

# 2. 查看 PVC 事件
echo "2. 查看 PVC 事件..."
kubectl describe pvc "$PVC_NAME" | grep -A 20 "Events:" | head -25
echo ""

# 3. 检查 StorageClass
echo "3. 检查 StorageClass..."
STORAGE_CLASS=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
echo "StorageClass: $STORAGE_CLASS"

if [ "$STORAGE_CLASS" = "longhorn" ]; then
    echo "检查 longhorn StorageClass..."
    kubectl get storageclass longhorn -o yaml | grep -E "provisioner|allowVolumeExpansion"
    echo ""
    
    # 检查 provisioner
    PROVISIONER=$(kubectl get storageclass longhorn -o jsonpath='{.provisioner}' 2>/dev/null)
    echo "Provisioner: $PROVISIONER"
    
    # 检查 CSI Driver
    if kubectl get csidriver "$PROVISIONER" &>/dev/null; then
        echo "✓ CSI Driver 存在"
    else
        echo "❌ CSI Driver 不存在: $PROVISIONER"
        echo "这是问题所在！"
    fi
else
    echo "⚠️  StorageClass 不是 longhorn"
fi
echo ""

# 4. 检查 CSI 组件
echo "4. 检查 CSI 组件..."
CSI_PODS=$(kubectl get pods -n longhorn-system -o name 2>/dev/null | grep -E "csi|driver" || true)
if [ -n "$CSI_PODS" ]; then
    echo "CSI 相关 Pods:"
    kubectl get pods -n longhorn-system | grep -E "csi|driver"
    echo ""
    
    # 检查每个 Pod 的状态
    echo "详细状态:"
    for pod in $CSI_PODS; do
        POD_NAME=$(echo $pod | cut -d'/' -f2)
        STATUS=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
        READY=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
        echo "  $POD_NAME: $STATUS (Ready: $READY)"
        
        if [ "$STATUS" != "Running" ] && [ "$STATUS" != "Succeeded" ]; then
            echo "    ⚠️  Pod 未运行，查看日志:"
            kubectl logs -n longhorn-system "$POD_NAME" --tail=5 2>&1 | sed 's/^/      /'
        fi
    done
else
    echo "❌ 没有找到 CSI 相关 Pods"
    echo "这是问题所在！"
fi
echo ""

# 5. 检查 Longhorn Node
echo "5. 检查 Longhorn Node..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "节点名称: $NODE_NAME"

if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "✓ Longhorn Node 资源存在"
    echo ""
    
    # 检查磁盘配置
    echo "磁盘配置:"
    DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
    if [ -n "$DISKS" ] && [ "$DISKS" != "null" ]; then
        kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
        kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 20 "disks:" | head -25
    else
        echo "❌ 没有配置磁盘（这是问题所在！）"
    fi
    echo ""
    
    # 检查磁盘状态
    echo "磁盘状态:"
    DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' 2>/dev/null)
    if [ -n "$DISK_STATUS" ] && [ "$DISK_STATUS" != "null" ]; then
        kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' | python3 -m json.tool 2>/dev/null || \
        kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 30 "diskStatus:" | head -35
        
        # 检查是否有 not ready 的磁盘
        if echo "$DISK_STATUS" | grep -q "not ready"; then
            echo ""
            echo "❌ 发现未就绪的磁盘"
        fi
    else
        echo "⚠️  磁盘状态未报告"
    fi
else
    echo "❌ Longhorn Node 资源不存在"
    echo "等待 Longhorn Manager 创建 Node 资源..."
fi
echo ""

# 6. 检查 Longhorn Manager
echo "6. 检查 Longhorn Manager..."
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MANAGER_POD" ]; then
    MANAGER_STATUS=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Manager Pod: $MANAGER_POD"
    echo "状态: $MANAGER_STATUS"
    
    if [ "$MANAGER_STATUS" != "Running" ]; then
        echo "⚠️  Manager 未运行，查看日志:"
        kubectl logs -n longhorn-system "$MANAGER_POD" --tail=20 2>&1 | tail -10
    fi
else
    echo "❌ Manager Pod 不存在"
fi
echo ""

# 7. 检查事件
echo "7. 检查相关事件..."
kubectl get events --field-selector involvedObject.name=$PVC_NAME --sort-by='.lastTimestamp' | tail -10
echo ""

# 8. 总结和建议
echo "=== 诊断总结 ==="
echo ""

PROBLEMS=0

# 检查 CSI Driver
if ! kubectl get csidriver driver.longhorn.io &>/dev/null; then
    echo "❌ 问题 1: CSI Driver 未安装"
    echo "   解决: 等待 longhorn-driver-deployer 完成，或重启它"
    echo "   kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
    PROBLEMS=$((PROBLEMS + 1))
fi

# 检查 CSI Pods
CSI_RUNNING=$(kubectl get pods -n longhorn-system 2>/dev/null | grep -E "csi-provisioner|csi-attacher" | grep -c "Running" || echo "0")
CSI_RUNNING=$(echo "$CSI_RUNNING" | tr -d ' \n' | head -1)  # 清理空格和换行
if [ -z "$CSI_RUNNING" ] || [ "$CSI_RUNNING" = "" ]; then
    CSI_RUNNING=0
fi
if [ "$CSI_RUNNING" -lt 2 ]; then
    echo "❌ 问题 2: CSI 组件未完全运行"
    echo "   解决: 检查 CSI Pods 状态和日志"
    echo "   kubectl get pods -n longhorn-system | grep csi"
    PROBLEMS=$((PROBLEMS + 1))
fi

# 检查磁盘配置
if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
    if [ -z "$DISKS" ] || [ "$DISKS" = "null" ]; then
        echo "❌ 问题 3: Longhorn Node 没有磁盘配置（最常见）"
        echo "   解决: 配置磁盘"
        echo "   ./scripts/configure-longhorn-disk.sh /mnt/longhorn"
        echo "   或通过 Longhorn UI: Nodes → $NODE_NAME → Disks → Add Disk"
        PROBLEMS=$((PROBLEMS + 1))
    else
        # 检查磁盘状态
        DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' 2>/dev/null)
        if echo "$DISK_STATUS" | grep -q "not ready"; then
            echo "❌ 问题 4: 磁盘未就绪"
            echo "   解决: 修复磁盘 UUID 不匹配或其他问题"
            echo "   ./scripts/fix-longhorn-disk-uuid.sh /mnt/longhorn"
            PROBLEMS=$((PROBLEMS + 1))
        fi
    fi
fi

if [ $PROBLEMS -eq 0 ]; then
    echo "✓ 未发现明显问题"
    echo ""
    echo "如果 PVC 仍然 Pending，可能原因:"
    echo "  1. 存储空间不足"
    echo "  2. 网络问题"
    echo "  3. Longhorn 组件正在初始化"
    echo ""
    echo "建议:"
    echo "  1. 等待几分钟，让 Longhorn 完全初始化"
    echo "  2. 检查 Longhorn Manager 日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo "  3. 检查 CSI Provisioner 日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-csi-provisioner --tail=50"
else
    echo ""
    echo "发现 $PROBLEMS 个问题，请先解决这些问题"
fi

echo ""
echo "=== 完成 ==="

