#!/bin/bash

# 重新创建 Wukong 资源（带用户配置）

echo "=== 重新创建 Wukong 资源 ==="

# 1. 检查当前 Wukong 资源
echo -e "\n1. 检查当前 Wukong 资源..."
WUKONG_NAME="ubuntu-noble-local"
if kubectl get wukong "$WUKONG_NAME" 2>/dev/null | grep -q "$WUKONG_NAME"; then
    echo "找到 Wukong 资源: $WUKONG_NAME"
    echo ""
    echo "当前配置:"
    kubectl get wukong "$WUKONG_NAME" -o yaml | grep -A 5 "spec:" | head -10
    echo ""
    
    # 备份当前配置
    BACKUP_FILE="/tmp/wukong-backup-$(date +%Y%m%d-%H%M%S).yaml"
    kubectl get wukong "$WUKONG_NAME" -o yaml > "$BACKUP_FILE"
    echo "✓ 已备份到: $BACKUP_FILE"
else
    echo "⚠️  未找到 Wukong 资源: $WUKONG_NAME"
fi

# 2. 检查 CRD 是否已更新
echo -e "\n2. 检查 CRD 是否已更新..."
if kubectl get crd wukongs.vm.novasphere.dev 2>/dev/null | grep -q wukong; then
    echo "✓ Wukong CRD 已安装"
    echo "检查 CRD 是否包含 cloudInitUser 字段..."
    if kubectl get crd wukongs.vm.novasphere.dev -o yaml | grep -q "cloudInitUser"; then
        echo "✓ CRD 包含 cloudInitUser 字段"
    else
        echo "⚠️  CRD 不包含 cloudInitUser 字段，需要更新 CRD"
        echo "运行: make manifests && make install"
        read -p "是否现在更新 CRD？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "更新 CRD..."
            make manifests
            make install
            echo "等待 CRD 更新..."
            sleep 5
        else
            echo "跳过 CRD 更新，继续..."
        fi
    fi
else
    echo "❌ Wukong CRD 未安装"
    echo "运行: make install"
    exit 1
fi

# 3. 停止并删除 VM（如果存在）
echo -e "\n3. 停止并删除 VM（如果存在）..."
VM_NAME="${WUKONG_NAME}-vm"
if kubectl get vm "$VM_NAME" 2>/dev/null | grep -q "$VM_NAME"; then
    echo "找到 VM: $VM_NAME"
    echo "停止 VM..."
    virtctl stop "$VM_NAME" 2>/dev/null || kubectl patch vm "$VM_NAME" --type merge -p '{"spec":{"running":false}}' 2>/dev/null || true
    sleep 3
    echo "删除 VM..."
    kubectl delete vm "$VM_NAME" --wait=false 2>/dev/null || true
fi

# 4. 删除 VMI（如果存在）
echo -e "\n4. 删除 VMI（如果存在）..."
if kubectl get vmi "$VM_NAME" 2>/dev/null | grep -q "$VM_NAME"; then
    echo "删除 VMI..."
    kubectl delete vmi "$VM_NAME" --wait=false 2>/dev/null || true
fi

# 5. 删除 DataVolume 和 PVC（如果存在）
echo -e "\n5. 清理存储资源..."
if kubectl get datavolume "${WUKONG_NAME}-system" 2>/dev/null | grep -q system; then
    echo "删除 DataVolume..."
    kubectl delete datavolume "${WUKONG_NAME}-system" --wait=false 2>/dev/null || true
fi

if kubectl get pvc "${WUKONG_NAME}-system" 2>/dev/null | grep -q system; then
    echo "删除 PVC..."
    kubectl delete pvc "${WUKONG_NAME}-system" --wait=false 2>/dev/null || true
fi

# 6. 删除 Wukong 资源
echo -e "\n6. 删除 Wukong 资源..."
if kubectl get wukong "$WUKONG_NAME" 2>/dev/null | grep -q "$WUKONG_NAME"; then
    echo "删除 Wukong..."
    kubectl delete wukong "$WUKONG_NAME" --wait=false 2>/dev/null || true
    echo "等待资源清理..."
    sleep 5
else
    echo "Wukong 资源不存在，跳过删除"
fi

# 7. 生成密码哈希（如果需要）
echo -e "\n7. 准备用户配置..."
read -p "是否配置用户和密码？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "生成密码哈希..."
    read -sp "请输入密码: " USER_PASSWORD
    echo ""
    echo ""
    
    if [ -z "$USER_PASSWORD" ]; then
        echo "⚠️  未输入密码，将使用示例配置"
        PASSWORD_HASH=""
    else
        # 生成密码哈希
        if command -v python3 &> /dev/null; then
            PASSWORD_HASH=$(python3 -c "import crypt; print(crypt.crypt('$USER_PASSWORD', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null)
        elif command -v openssl &> /dev/null; then
            PASSWORD_HASH=$(echo -n "$USER_PASSWORD" | openssl passwd -1 -stdin 2>/dev/null)
        else
            echo "⚠️  无法生成密码哈希，请手动生成"
            PASSWORD_HASH=""
        fi
        
        if [ -n "$PASSWORD_HASH" ]; then
            echo "✓ 密码哈希已生成"
        else
            echo "⚠️  密码哈希生成失败，将使用明文密码（不推荐）"
            PASSWORD_HASH=""
        fi
    fi
else
    PASSWORD_HASH=""
fi

# 8. 创建新的 Wukong 资源
echo -e "\n8. 创建新的 Wukong 资源..."

# 读取示例文件
SAMPLE_FILE="config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "❌ 示例文件不存在: $SAMPLE_FILE"
    exit 1
fi

# 创建临时文件
TEMP_FILE=$(mktemp)
cp "$SAMPLE_FILE" "$TEMP_FILE"

# 如果生成了密码哈希，更新配置
if [ -n "$PASSWORD_HASH" ]; then
    echo "更新配置，使用密码哈希..."
    # 使用 sed 替换 passwordHash
    sed -i.bak "s/passwordHash:.*/passwordHash: \"$PASSWORD_HASH\"/" "$TEMP_FILE" 2>/dev/null || \
    sed -i "s/passwordHash:.*/passwordHash: \"$PASSWORD_HASH\"/" "$TEMP_FILE"
    # 注释掉 password 字段（如果存在）
    sed -i.bak 's/^[[:space:]]*password:.*/# &/' "$TEMP_FILE" 2>/dev/null || \
    sed -i 's/^[[:space:]]*password:.*/# &/' "$TEMP_FILE"
    rm -f "${TEMP_FILE}.bak" 2>/dev/null || true
fi

# 应用配置
echo "应用 Wukong 配置..."
kubectl apply -f "$TEMP_FILE"

# 清理临时文件
rm -f "$TEMP_FILE"

# 9. 检查状态
echo -e "\n9. 检查状态..."
sleep 3
kubectl get wukong "$WUKONG_NAME"
kubectl get vm 2>/dev/null | grep "$WUKONG_NAME" || echo "VM 还未创建（等待 controller 处理）"

echo -e "\n=== 完成 ==="
echo ""
echo "下一步："
echo "  1. 等待 Controller 创建 VM: kubectl get vm"
echo "  2. 等待 VM 启动: kubectl get vmi"
echo "  3. 登录 VM: virtctl console ${WUKONG_NAME}-vm"
echo ""
echo "如果遇到问题，检查："
echo "  - Controller 日志（如果使用 make run）"
echo "  - Wukong 状态: kubectl get wukong $WUKONG_NAME -o yaml"
echo "  - 事件: kubectl get events --sort-by='.lastTimestamp' | tail -20"

