#!/bin/bash

# 为 VM 添加用户和密码

echo "=== 为 VM 添加用户和密码 ==="

# 1. 获取 VM 名称
VM_NAME=$(kubectl get vm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$VM_NAME" ]; then
    echo "❌ 未找到 VM"
    exit 1
fi

echo "VM 名称: $VM_NAME"

# 2. 获取 VMI 名称
VMI_NAME=$(kubectl get vmi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$VMI_NAME" ]; then
    echo "⚠️  未找到 VMI，VM 可能还未启动"
    echo "等待 VM 启动..."
    sleep 10
    VMI_NAME=$(kubectl get vmi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$VMI_NAME" ]; then
        echo "❌ VM 仍未启动"
        exit 1
    fi
fi

echo "VMI 名称: $VMI_NAME"

# 3. 获取用户名和密码
echo -e "\n配置用户和密码:"
read -p "用户名 (默认: ubuntu): " USERNAME
USERNAME=${USERNAME:-ubuntu}

read -sp "密码: " PASSWORD
echo ""
if [ -z "$PASSWORD" ]; then
    echo "❌ 密码不能为空"
    exit 1
fi

# 4. 生成密码哈希
echo -e "\n生成密码哈希..."
PASSWORD_HASH=$(echo -n "$PASSWORD" | openssl passwd -1 -stdin 2>/dev/null)
if [ -z "$PASSWORD_HASH" ]; then
    echo "⚠️  无法使用 openssl，尝试使用 Python..."
    PASSWORD_HASH=$(python3 -c "import crypt; print(crypt.crypt('$PASSWORD', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null)
    if [ -z "$PASSWORD_HASH" ]; then
        echo "❌ 无法生成密码哈希，请安装 openssl 或 Python"
        exit 1
    fi
fi

# 5. 创建 cloud-init 配置
echo -e "\n创建 cloud-init 配置..."
CLOUD_INIT_CONFIG=$(cat <<EOF
#cloud-config
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $PASSWORD_HASH
    ssh_authorized_keys: []
    groups: sudo, adm, dialout, cdrom, floppy, audio, dip, video, plugdev, netdev

# 允许密码认证
ssh_pwauth: true
disable_root: false

# 网络配置
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
)

# 6. 更新 VM 的 cloud-init 配置
echo -e "\n更新 VM 的 cloud-init 配置..."

# 转义 cloud-init 配置中的特殊字符
ESCAPED_CONFIG=$(echo "$CLOUD_INIT_CONFIG" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 创建临时 patch 文件
PATCH_FILE=$(mktemp)
cat > "$PATCH_FILE" <<EOF
[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "cloudinitdisk",
      "cloudInitNoCloud": {
        "userData": "$ESCAPED_CONFIG"
      }
    }
  }
]
EOF

kubectl patch vm "$VM_NAME" --type json -p="$(cat $PATCH_FILE)" 2>&1
PATCH_RESULT=$?

rm -f "$PATCH_FILE"

if [ $PATCH_RESULT -eq 0 ]; then
    echo "✓ 已更新 VM 配置"
else
    echo "⚠️  自动更新失败，请手动编辑 VM"
    echo ""
    echo "运行以下命令编辑 VM:"
    echo "  kubectl edit vm $VM_NAME"
    echo ""
    echo "在 spec.template.spec.volumes 中添加以下内容:"
    echo "  - name: cloudinitdisk"
    echo "    cloudInitNoCloud:"
    echo "      userData: |"
    echo "$CLOUD_INIT_CONFIG" | sed 's/^/        /'
    echo ""
    read -p "是否现在手动编辑？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl edit vm "$VM_NAME"
    else
        echo "请稍后手动编辑 VM 配置"
    fi
fi

# 7. 重启 VM 以应用配置
echo -e "\n重启 VM 以应用配置..."
read -p "是否重启 VM？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v virtctl &> /dev/null; then
        echo "停止 VM..."
        virtctl stop "$VMI_NAME" 2>/dev/null || kubectl patch vm "$VM_NAME" --type merge -p '{"spec":{"running":false}}'
        sleep 5
        echo "启动 VM..."
        virtctl start "$VM_NAME" 2>/dev/null || kubectl patch vm "$VM_NAME" --type merge -p '{"spec":{"running":true}}'
        echo "✓ VM 已重启"
    else
        echo "使用 kubectl 重启 VM..."
        kubectl patch vm "$VM_NAME" --type merge -p '{"spec":{"running":false}}'
        sleep 5
        kubectl patch vm "$VM_NAME" --type merge -p '{"spec":{"running":true}}'
        echo "✓ VM 已重启"
    fi
else
    echo "跳过重启，请手动重启 VM:"
    echo "  virtctl restart $VM_NAME"
    echo "  或: kubectl patch vm $VM_NAME --type merge -p '{\"spec\":{\"running\":false}}'"
    echo "      kubectl patch vm $VM_NAME --type merge -p '{\"spec\":{\"running\":true}}'"
fi

echo -e "\n=== 完成 ==="
echo ""
echo "配置信息:"
echo "  用户名: $USERNAME"
echo "  密码: (已设置)"
echo ""
echo "等待 VM 重启后，可以使用以下方式登录:"
echo "  1. 控制台: virtctl console $VMI_NAME"
echo "  2. SSH: ssh $USERNAME@<VM_IP>"
echo ""
echo "注意: 如果 VM 已经运行，需要重启才能应用 cloud-init 配置"

