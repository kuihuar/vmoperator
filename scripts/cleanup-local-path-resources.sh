#!/bin/bash

# 清理使用 local-path StorageClass 的资源

echo "=== 清理 local-path 相关资源 ==="
echo ""

# 确认
read -p "确定要删除所有使用 local-path StorageClass 的资源吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo "开始清理..."
echo ""

# 1. 查找所有使用 local-path 的 PVC
echo "1. 查找使用 local-path 的 PVC..."
LOCAL_PATH_PVCS=$(kubectl get pvc --all-namespaces -o json | \
    jq -r '.items[] | select(.spec.storageClassName == "local-path" or .spec.storageClassName == "local-path-storage") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || \
    kubectl get pvc --all-namespaces -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
    kubectl get pvc --all-namespaces -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path-storage")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "$LOCAL_PATH_PVCS" ]; then
    echo "  未找到使用 local-path 的 PVC"
else
    echo "  找到以下 PVC:"
    echo "$LOCAL_PATH_PVCS" | while read pvc; do
        if [ -n "$pvc" ]; then
            echo "    - $pvc"
        fi
    done
    echo ""
    
    # 删除 PVC
    echo "  删除 PVC..."
    echo "$LOCAL_PATH_PVCS" | while read pvc; do
        if [ -n "$pvc" ]; then
            NAMESPACE=$(echo $pvc | cut -d'/' -f1)
            NAME=$(echo $pvc | cut -d'/' -f2)
            echo "    删除 $NAMESPACE/$NAME..."
            kubectl delete pvc -n "$NAMESPACE" "$NAME" --ignore-not-found=true
        fi
    done
fi
echo ""

# 2. 查找相关的 DataVolume
echo "2. 查找相关的 DataVolume..."
if kubectl get crd datavolumes.cdi.kubevirt.io &>/dev/null; then
    LOCAL_PATH_DVS=$(kubectl get datavolume --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.pvc.storageClassName == "local-path" or .spec.pvc.storageClassName == "local-path-storage") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || \
        kubectl get datavolume --all-namespaces -o jsonpath='{range .items[?(@.spec.pvc.storageClassName=="local-path")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
        kubectl get datavolume --all-namespaces -o jsonpath='{range .items[?(@.spec.pvc.storageClassName=="local-path-storage")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    
    if [ -z "$LOCAL_PATH_DVS" ]; then
        echo "  未找到使用 local-path 的 DataVolume"
    else
        echo "  找到以下 DataVolume:"
        echo "$LOCAL_PATH_DVS" | while read dv; do
            if [ -n "$dv" ]; then
                echo "    - $dv"
            fi
        done
        echo ""
        
        # 删除 DataVolume
        echo "  删除 DataVolume..."
        echo "$LOCAL_PATH_DVS" | while read dv; do
            if [ -n "$dv" ]; then
                NAMESPACE=$(echo $dv | cut -d'/' -f1)
                NAME=$(echo $dv | cut -d'/' -f2)
                echo "    删除 $NAMESPACE/$NAME..."
                kubectl delete datavolume -n "$NAMESPACE" "$NAME" --ignore-not-found=true
            fi
        done
    fi
else
    echo "  DataVolume CRD 不存在，跳过"
fi
echo ""

# 3. 查找相关的 Wukong 资源（通过 PVC 名称推断）
echo "3. 查找相关的 Wukong 资源..."
if kubectl get crd wukongs.vm.novasphere.dev &>/dev/null; then
    # 从 PVC 名称推断 Wukong 名称（格式: <wukong-name>-<disk-name>）
    WUKONG_NAMES=$(echo "$LOCAL_PATH_PVCS" | while read pvc; do
        if [ -n "$pvc" ]; then
            NAME=$(echo $pvc | cut -d'/' -f2)
            # 提取 Wukong 名称（去掉 -system, -data 等后缀）
            WUKONG_NAME=$(echo $NAME | sed 's/-system$//' | sed 's/-data$//' | sed 's/-.*$//')
            echo "$WUKONG_NAME"
        fi
    done | sort -u)
    
    if [ -z "$WUKONG_NAMES" ]; then
        echo "  未找到相关的 Wukong 资源"
    else
        echo "  可能相关的 Wukong 资源:"
        echo "$WUKONG_NAMES" | while read wukong; do
            if [ -n "$wukong" ]; then
                # 检查是否存在
                if kubectl get wukong "$wukong" &>/dev/null 2>&1; then
                    # 检查是否使用 local-path
                    SC=$(kubectl get wukong "$wukong" -o jsonpath='{.spec.disks[*].storageClassName}' 2>/dev/null)
                    if echo "$SC" | grep -q "local-path"; then
                        echo "    - $wukong (使用 local-path)"
                        read -p "      删除 $wukong? (y/N): " -n 1 -r
                        echo ""
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            kubectl delete wukong "$wukong" --ignore-not-found=true
                        fi
                    else
                        echo "    - $wukong (不使用 local-path，跳过)"
                    fi
                fi
            fi
        done
    fi
else
    echo "  Wukong CRD 不存在，跳过"
fi
echo ""

# 4. 查找相关的 VM/VMI 资源
echo "4. 查找相关的 VM/VMI 资源..."
if kubectl get crd virtualmachines.kubevirt.io &>/dev/null; then
    # 查找所有 VM
    VMS=$(kubectl get vm --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    
    if [ -z "$VMS" ]; then
        echo "  未找到 VM 资源"
    else
        echo "  检查 VM 是否使用 local-path 存储..."
        echo "$VMS" | while read vm; do
            if [ -n "$vm" ]; then
                NAMESPACE=$(echo $vm | cut -d'/' -f1)
                NAME=$(echo $vm | cut -d'/' -f2)
                # 检查 VM 的 PVC 引用
                VM_PVCS=$(kubectl get vm -n "$NAMESPACE" "$NAME" -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}' 2>/dev/null)
                if [ -n "$VM_PVCS" ]; then
                    for pvc_name in $VM_PVCS; do
                        PVC_SC=$(kubectl get pvc -n "$NAMESPACE" "$pvc_name" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
                        if echo "$PVC_SC" | grep -q "local-path"; then
                            echo "    - $vm (使用 local-path)"
                            read -p "      删除 $vm? (y/N): " -n 1 -r
                            echo ""
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                kubectl delete vm -n "$NAMESPACE" "$NAME" --ignore-not-found=true
                            fi
                            break
                        fi
                    done
                fi
            fi
        done
    fi
else
    echo "  VM CRD 不存在，跳过"
fi
echo ""

# 5. 等待资源删除
echo "5. 等待资源删除完成..."
sleep 3

# 6. 检查剩余资源
echo "6. 检查剩余资源..."
REMAINING_PVCS=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.storageClassName == "local-path" or .spec.storageClassName == "local-path-storage") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || \
    kubectl get pvc --all-namespaces -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "$REMAINING_PVCS" ]; then
    echo "  ✅ 所有 local-path PVC 已删除"
else
    echo "  ⚠️  仍有以下 PVC 未删除:"
    echo "$REMAINING_PVCS" | while read pvc; do
        if [ -n "$pvc" ]; then
            echo "    - $pvc"
        fi
    done
    echo ""
    echo "  可能需要手动删除或等待删除完成"
fi
echo ""

# 7. 清理 PV（如果存在）
echo "7. 检查相关的 PV..."
# local-path 的 PV 通常会自动清理，但我们可以检查
RELEASED_PVS=$(kubectl get pv -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.storageClassName == "local-path" or .spec.storageClassName == "local-path-storage") | select(.status.phase == "Released") | .metadata.name' 2>/dev/null || \
    kubectl get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "$RELEASED_PVS" ]; then
    echo "  未找到 Released 状态的 local-path PV"
else
    echo "  找到以下 Released 状态的 PV:"
    echo "$RELEASED_PVS" | while read pv; do
        if [ -n "$pv" ]; then
            echo "    - $pv"
        fi
    done
    echo ""
    echo "  注意: local-path 的 PV 通常会自动清理，无需手动删除"
fi
echo ""

echo "=== 清理完成 ==="
echo ""
echo "提示:"
echo "  - 如果仍有资源未删除，可能需要等待一段时间"
echo "  - 检查: kubectl get pvc --all-namespaces | grep local-path"
echo "  - 检查: kubectl get datavolume --all-namespaces | grep local-path"

