#!/bin/bash

# 检查 Longhorn 可用版本

echo "=== Longhorn 版本检查 ==="
echo ""

# 1. 获取最新版本
echo "1. 最新版本:"
LATEST_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
if [ -n "$LATEST_VERSION" ]; then
    echo "  ✓ $LATEST_VERSION"
    
    # 获取发布日期
    PUBLISHED_AT=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep published_at | cut -d '"' -f 4)
    if [ -n "$PUBLISHED_AT" ]; then
        echo "  发布日期: $PUBLISHED_AT"
    fi
else
    echo "  ❌ 无法获取最新版本"
fi
echo ""

# 2. 获取最近 10 个版本
echo "2. 最近 10 个版本:"
curl -s https://api.github.com/repos/longhorn/longhorn/releases | \
    grep -E "tag_name|published_at" | \
    head -20 | \
    while IFS= read -r line1 && IFS= read -r line2; do
        VERSION=$(echo "$line1" | cut -d '"' -f 4)
        DATE=$(echo "$line2" | cut -d '"' -f 4 | cut -d 'T' -f 1)
        echo "  - $VERSION (发布: $DATE)"
    done
echo ""

# 3. 检查当前安装的版本（如果已安装）
echo "3. 当前安装的版本:"
if kubectl get namespace longhorn-system &>/dev/null; then
    # 尝试从 Manager Pod 获取版本
    MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$MANAGER_POD" ]; then
        # 从镜像标签获取版本
        IMAGE=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
        if [ -n "$IMAGE" ]; then
            VERSION=$(echo "$IMAGE" | grep -oP 'longhorn-manager:\K[^ ]+' | cut -d ':' -f 2 || echo "未知")
            echo "  $VERSION (从镜像: $IMAGE)"
        fi
    else
        echo "  Longhorn 未运行"
    fi
else
    echo "  Longhorn 未安装"
fi
echo ""

# 4. 版本建议
echo "4. 版本建议:"
echo "  ✅ 推荐使用最新稳定版本: $LATEST_VERSION"
echo "  📋 查看所有版本: https://github.com/longhorn/longhorn/releases"
echo "  🔍 查看版本说明: https://github.com/longhorn/longhorn/releases/tag/$LATEST_VERSION"
echo ""

# 5. 安装命令示例
echo "5. 安装命令示例:"
echo ""
echo "  使用最新版本（推荐）:"
echo "    ./scripts/install-longhorn.sh kubectl latest"
echo "    ./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn"
echo ""
echo "  使用特定版本:"
echo "    ./scripts/install-longhorn.sh kubectl v1.6.0"
echo "    ./scripts/reinstall-longhorn.sh kubectl v1.6.0 /mnt/longhorn"
echo ""

echo "=== 完成 ==="

