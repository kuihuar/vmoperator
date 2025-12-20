#!/bin/bash

# 生成密码哈希工具

echo "=== 生成密码哈希 ==="
echo ""

if [ $# -eq 0 ]; then
    echo "请输入密码（输入时不会显示，这是正常的安全行为）:"
    read -sp "密码: " PASSWORD
    echo ""
    echo ""
    
    # 确认密码
    read -sp "再次输入密码确认: " PASSWORD_CONFIRM
    echo ""
    echo ""
    
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "❌ 两次输入的密码不一致"
        exit 1
    fi
    
    if [ -z "$PASSWORD" ]; then
        echo "❌ 密码不能为空"
        exit 1
    fi
    
    echo "✓ 密码已确认"
    echo ""
else
    PASSWORD="$1"
    if [ -z "$PASSWORD" ]; then
        echo "❌ 密码不能为空"
        exit 1
    fi
fi

echo -e "\n生成密码哈希..."
echo ""

# 方法 1: 使用 openssl (MD5, 快速)
if command -v openssl &> /dev/null; then
    HASH_MD5=$(echo -n "$PASSWORD" | openssl passwd -1 -stdin 2>/dev/null)
    if [ -n "$HASH_MD5" ]; then
        echo "方法 1: 使用 openssl (MD5):"
        echo "  $HASH_MD5"
        echo ""
    fi
fi

# 方法 2: 使用 Python (SHA512, 更安全，推荐)
if command -v python3 &> /dev/null; then
    HASH_SHA512=$(python3 -c "import crypt; print(crypt.crypt('$PASSWORD', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null)
    if [ -n "$HASH_SHA512" ]; then
        echo "方法 2: 使用 Python (SHA512, 推荐):"
        echo "  $HASH_SHA512"
        echo ""
    fi
fi

# 方法 3: 使用 mkpasswd (如果可用)
if command -v mkpasswd &> /dev/null; then
    HASH_MKPASSWD=$(mkpasswd -m sha-512 "$PASSWORD" 2>/dev/null)
    if [ -n "$HASH_MKPASSWD" ]; then
        echo "方法 3: 使用 mkpasswd (SHA512):"
        echo "  $HASH_MKPASSWD"
        echo ""
    fi
fi

echo "=== 使用说明 ==="
echo ""
echo "在 Wukong YAML 中使用:"
echo "  cloudInitUser:"
echo "    name: ubuntu"
echo "    passwordHash: \"<上面的哈希值>\""
echo ""
echo "注意:"
echo "  - SHA512 哈希更安全，推荐使用"
echo "  - MD5 哈希兼容性好，但安全性较低"
echo "  - 选择其中一个哈希值使用即可"
echo ""
echo "提示:"
echo "  - 密码输入时不显示是正常的安全行为"
echo "  - 如果需要在命令行直接提供密码，使用: ./scripts/generate-password-hash.sh 'your-password'"

