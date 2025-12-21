#!/bin/bash

# 快速清理 local-path 资源（非交互式）

echo "=== 快速清理 local-path 相关资源 ==="
echo ""

# 1. 删除所有使用 local-path 的 PVC
echo "1. 删除使用 local-path 的 PVC..."
kubectl get pvc --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.storageClassName == "local-path" or .spec.storageClassName == "local-path-storage") | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null | \
    while read namespace name; do
        if [ -n "$namespace" ] && [ -n "$name" ]; then
            echo "  删除 $namespace/$name..."
            kubectl delete pvc -n "$namespace" "$name" --ignore-not-found=true 2>/dev/null
        fi
    done

# 如果没有 jq，使用 jsonpath
if ! command -v jq &> /dev/null; then
    echo "  使用 jsonpath 查找 PVC..."
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        kubectl get pvc -n "$ns" -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | \
        while read name; do
            if [ -n "$name" ]; then
                echo "  删除 $ns/$name..."
                kubectl delete pvc -n "$ns" "$name" --ignore-not-found=true 2>/dev/null
            fi
        done
    done
fi
echo ""

# 2. 删除相关的 DataVolume
echo "2. 删除使用 local-path 的 DataVolume..."
if kubectl get crd datavolumes.cdi.kubevirt.io &>/dev/null; then
    kubectl get datavolume --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.pvc.storageClassName == "local-path" or .spec.pvc.storageClassName == "local-path-storage") | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null | \
        while read namespace name; do
            if [ -n "$namespace" ] && [ -n "$name" ]; then
                echo "  删除 $namespace/$name..."
                kubectl delete datavolume -n "$namespace" "$name" --ignore-not-found=true 2>/dev/null
            fi
        done
    
    # 如果没有 jq，使用 jsonpath
    if ! command -v jq &> /dev/null; then
        for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
            kubectl get datavolume -n "$ns" -o jsonpath='{range .items[?(@.spec.pvc.storageClassName=="local-path")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | \
            while read name; do
                if [ -n "$name" ]; then
                    echo "  删除 $ns/$name..."
                    kubectl delete datavolume -n "$ns" "$name" --ignore-not-found=true 2>/dev/null
                fi
            done
        done
    fi
else
    echo "  DataVolume CRD 不存在，跳过"
fi
echo ""

# 3. 查找并提示删除相关的 Wukong 资源
echo "3. 查找相关的 Wukong 资源..."
if kubectl get crd wukongs.vm.novasphere.dev &>/dev/null; then
    WUKONGS=$(kubectl get wukong --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    if [ -n "$WUKONGS" ]; then
        echo "$WUKONGS" | while read namespace name; do
            if [ -n "$namespace" ] && [ -n "$name" ]; then
                # 检查是否使用 local-path
                SC=$(kubectl get wukong -n "$namespace" "$name" -o jsonpath='{.spec.disks[*].storageClassName}' 2>/dev/null)
                if echo "$SC" | grep -q "local-path"; then
                    echo "  找到使用 local-path 的 Wukong: $namespace/$name"
                    echo "  提示: 如需删除，运行: kubectl delete wukong -n $namespace $name"
                fi
            fi
        done
    else
        echo "  未找到 Wukong 资源"
    fi
else
    echo "  Wukong CRD 不存在，跳过"
fi
echo ""

# 4. 等待删除完成
echo "4. 等待删除完成..."
sleep 2

# 5. 显示剩余资源
echo "5. 检查剩余资源..."
REMAINING=$(kubectl get pvc --all-namespaces 2>/dev/null | grep "local-path" || echo "")
if [ -z "$REMAINING" ]; then
    echo "  ✅ 所有 local-path PVC 已删除"
else
    echo "  ⚠️  仍有以下 PVC:"
    echo "$REMAINING"
fi
echo ""

echo "=== 完成 ==="
echo ""
echo "提示:"
echo "  - 如果仍有资源，可能需要等待或手动删除"
echo "  - 检查: kubectl get pvc --all-namespaces | grep local-path"
echo "  - 检查: kubectl get datavolume --all-namespaces"

