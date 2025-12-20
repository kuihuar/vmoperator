#!/bin/bash

# 测试 Docker 镜像源可用性

echo "=== 测试 Docker 镜像源 ==="

test_mirror() {
    local url=$1
    local name=$2
    echo -n "测试 $name ($url): "
    if curl -s -I --connect-timeout 5 "$url" > /dev/null 2>&1; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "✓ 可用 (HTTP $HTTP_CODE)"
            return 0
        else
            echo "✗ 不可用 (HTTP $HTTP_CODE)"
            return 1
        fi
    else
        echo "✗ 无法连接"
        return 1
    fi
}

echo ""
AVAILABLE=()

# 测试各种镜像源
test_mirror "https://reg-mirror.qiniu.com" "七牛云" && AVAILABLE+=("https://reg-mirror.qiniu.com")
test_mirror "https://hub-mirror.c.163.com" "网易" && AVAILABLE+=("https://hub-mirror.c.163.com")
test_mirror "https://dockerhub.azk8s.cn" "Azure 中国" && AVAILABLE+=("https://dockerhub.azk8s.cn")
test_mirror "https://docker.mirrors.ustc.edu.cn" "中科大" && AVAILABLE+=("https://docker.mirrors.ustc.edu.cn")
test_mirror "https://mirror.ccs.tencentyun.com" "腾讯云" && AVAILABLE+=("https://mirror.ccs.tencentyun.com")

echo ""
if [ ${#AVAILABLE[@]} -gt 0 ]; then
    echo "✓ 可用的镜像源:"
    for mirror in "${AVAILABLE[@]}"; do
        echo "  - $mirror"
    done
else
    echo "✗ 没有可用的镜像源"
    echo ""
    echo "建议："
    echo "  1. 配置 VPN 或代理"
    echo "  2. 使用内网镜像仓库"
    echo "  3. 手动下载镜像"
fi

