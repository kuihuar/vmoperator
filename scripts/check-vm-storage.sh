#!/bin/bash

# 检查 VM 存储状态

echo "=== 检查 VM 存储状态 ==="

# 1. 获取 Wukong 名称
WUKONG_NAME=$(kubectl get wukong -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$WUKONG_NAME" ]; then
    echo "❌ 未找到 Wukong 资源"
    exit 1
fi

echo "Wukong 名称: $WUKONG_NAME"
echo ""

# 2. 检查 Wukong 磁盘配置
echo "1. Wukong 磁盘配置:"
kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.spec.disks[*]}' | jq '.' 2>/dev/null || \
kubectl get wukong "$WUKONG_NAME" -o yaml | grep -A 10 "disks:" | head -15
echo ""

# 3. 检查 PVC 状态
echo "2. PVC 状态:"
kubectl get pvc | grep "$WUKONG_NAME" || echo "  未找到 PVC"
echo ""

if kubectl get pvc 2>/dev/null | grep -q "$WUKONG_NAME"; then
    echo "PVC 详情:"
    for pvc in $(kubectl get pvc -o jsonpath='{.items[*].metadata.name}' | grep "$WUKONG_NAME"); do
        echo "--- PVC: $pvc ---"
        kubectl get pvc "$pvc" -o wide
        echo ""
        echo "容量和状态:"
        kubectl get pvc "$pvc" -o jsonpath='{.status.capacity.storage}{"\t"}{.status.phase}{"\n"}'
        echo ""
        
        # 检查绑定的 PV
        PV_NAME=$(kubectl get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
        if [ -n "$PV_NAME" ]; then
            echo "绑定的 PV: $PV_NAME"
            kubectl get pv "$PV_NAME" -o wide 2>/dev/null || echo "  PV 不存在"
            
            # 检查存储路径（如果是 local-path）
            STORAGE_CLASS=$(kubectl get pvc "$pvc" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
            if [ "$STORAGE_CLASS" = "local-path" ]; then
                echo "存储类型: local-path"
                echo "存储位置: /var/local-path-provisioner/pvc-<uuid>/"
                echo "（需要在节点上查看实际路径）"
            fi
        else
            echo "PV 未绑定（可能还在等待绑定）"
        fi
        echo ""
    done
fi

# 4. 检查 DataVolume 状态
echo "3. DataVolume 状态:"
kubectl get datavolume 2>/dev/null | grep "$WUKONG_NAME" || echo "  未找到 DataVolume"
echo ""

if kubectl get datavolume 2>/dev/null | grep -q "$WUKONG_NAME"; then
    for dv in $(kubectl get datavolume -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | grep "$WUKONG_NAME"); do
        echo "--- DataVolume: $dv ---"
        kubectl get datavolume "$dv" -o wide
        echo ""
        echo "状态:"
        kubectl get datavolume "$dv" -o jsonpath='{.status.phase}{"\n"}' 2>/dev/null
        echo ""
    done
fi

# 5. 检查 VM 磁盘挂载
echo "4. VM 磁盘挂载:"
VM_NAME="${WUKONG_NAME}-vm"
if kubectl get vm "$VM_NAME" 2>/dev/null | grep -q "$VM_NAME"; then
    echo "VM 磁盘配置:"
    kubectl get vm "$VM_NAME" -o yaml | grep -A 20 "volumes:" | head -25
else
    echo "  VM 不存在"
fi
echo ""

# 6. 检查存储使用（如果在 VM 内部）
echo "5. VM 内部存储使用:"
VMI_NAME=$(kubectl get vmi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$VMI_NAME" ]; then
    echo "VMI: $VMI_NAME"
    echo "（需要在 VM 内部执行 'df -h' 查看实际使用）"
    echo ""
    echo "连接到 VM 查看:"
    echo "  virtctl console $VMI_NAME"
    echo "  然后执行: df -h"
else
    echo "  VMI 不存在（VM 可能未启动）"
fi

# 7. 检查 StorageClass
echo ""
echo "6. StorageClass 配置:"
kubectl get storageclass
echo ""

# 8. 总结
echo "=== 存储总结 ==="
echo ""
echo "存储架构:"
echo "  Wukong Disks → PVC/DataVolume → PV → 节点存储"
echo ""
echo "数据持久化:"
echo "  ✅ 用户在 VM 中安装的软件和创建的数据都存储在 PVC 中"
echo "  ✅ 即使 VM 删除，PVC 仍然存在，数据保留"
echo "  ✅ 重新创建 VM 时，会挂载同一个 PVC，数据保留"
echo "  ⚠️  删除 PVC 会导致数据丢失"
echo ""
echo "存储位置:"
STORAGE_CLASS=$(kubectl get pvc 2>/dev/null | grep "$WUKONG_NAME" | head -1 | awk '{print $6}')
if [ "$STORAGE_CLASS" = "local-path" ]; then
    echo "  类型: local-path (k3s)"
    echo "  位置: /var/local-path-provisioner/pvc-<uuid>/"
    echo "  特点: 节点本地存储，节点故障可能导致数据丢失"
elif [ "$STORAGE_CLASS" = "hostpath" ]; then
    echo "  类型: hostpath"
    echo "  位置: 节点本地路径"
    echo "  特点: 节点本地存储"
else
    echo "  类型: $STORAGE_CLASS"
    echo "  （查看 StorageClass 配置了解详情）"
fi

echo ""
echo "=== 完成 ==="

