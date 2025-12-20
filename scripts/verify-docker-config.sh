#!/bin/bash

echo "🔍 验证 Docker Desktop 配置"
echo ""

# 1. 检查 Docker 是否运行
echo "1. 检查 Docker 状态..."
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker 未运行，请启动 Docker Desktop"
    exit 1
fi
echo "✅ Docker 正在运行"
echo ""

# 2. 检查不安全仓库配置
echo "2. 检查不安全仓库配置..."
INSECURE_REGISTRIES=$(docker info 2>/dev/null | grep -A 10 "Insecure Registries" | grep -v "Insecure Registries" | grep -v "^--$" | sed 's/^[[:space:]]*//')

if [ -z "$INSECURE_REGISTRIES" ]; then
    echo "❌ 未找到不安全仓库配置"
    echo ""
    echo "请检查 Docker Desktop 配置："
    echo "1. 打开 Docker Desktop"
    echo "2. Settings → Docker Engine"
    echo "3. 确保有以下配置："
    echo '   "insecure-registries": ['
    echo '     "localhost:5000",'
    echo '     "host.docker.internal:5000",'
    echo '     "127.0.0.1:5000"'
    echo '   ]'
    echo "4. 点击 Apply & Restart"
    exit 1
else
    echo "✅ 找到不安全仓库配置："
    echo "$INSECURE_REGISTRIES" | while read line; do
        if [ ! -z "$line" ]; then
            echo "   - $line"
        fi
    done
    
    # 检查是否包含需要的地址
    if echo "$INSECURE_REGISTRIES" | grep -q "localhost:5000\|host.docker.internal:5000\|127.0.0.1:5000"; then
        echo ""
        echo "✅ 配置包含所需的 registry 地址"
    else
        echo ""
        echo "⚠️  配置可能不完整，请确保包含："
        echo "   - localhost:5000"
        echo "   - host.docker.internal:5000"
        echo "   - 127.0.0.1:5000"
    fi
fi
echo ""

# 3. 检查本地 registry 是否运行
echo "3. 检查本地 registry..."
if docker ps | grep -q local-registry; then
    echo "✅ 本地 registry 正在运行"
    REGISTRY_IP=$(docker inspect local-registry 2>/dev/null | grep -A 5 "NetworkSettings" | grep "IPAddress" | head -1 | cut -d'"' -f4)
    if [ ! -z "$REGISTRY_IP" ]; then
        echo "   Registry IP: $REGISTRY_IP"
    fi
else
    echo "⚠️  本地 registry 未运行"
    if docker ps -a | grep -q local-registry; then
        echo "   尝试启动..."
        docker start local-registry
        sleep 2
        if docker ps | grep -q local-registry; then
            echo "✅ 本地 registry 已启动"
        else
            echo "❌ 启动失败"
        fi
    else
        echo "   需要创建 registry 容器"
        echo "   运行: docker run -d -p 5000:5000 --name local-registry registry:2"
    fi
fi
echo ""

# 4. 测试 registry 连接
echo "4. 测试 registry 连接..."
if curl -s http://localhost:5000/v2/_catalog > /dev/null 2>&1; then
    echo "✅ Registry 可访问"
    echo ""
    echo "当前镜像列表:"
    curl -s http://localhost:5000/v2/_catalog | jq . 2>/dev/null || curl -s http://localhost:5000/v2/_catalog
else
    echo "⚠️  Registry 无法访问"
    echo "   请检查 registry 是否运行: docker ps | grep local-registry"
fi
echo ""

# 5. 测试推送（如果镜像已标记）
echo "5. 检查镜像标记..."
if docker images | grep -q "host.docker.internal:5000/ubuntu-noble"; then
    echo "✅ 镜像已标记为 registry 地址"
    echo ""
    echo "镜像信息:"
    docker images | grep "host.docker.internal:5000/ubuntu-noble"
    echo ""
    echo "可以尝试推送:"
    echo "  docker push host.docker.internal:5000/ubuntu-noble:latest"
else
    echo "ℹ️  镜像尚未标记"
    echo ""
    echo "如果需要推送，先标记镜像:"
    echo "  docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest"
fi
echo ""

# 总结
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 配置检查总结"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if docker info 2>/dev/null | grep -q "host.docker.internal:5000\|localhost:5000"; then
    if docker ps | grep -q local-registry; then
        echo "✅ 配置正确，可以推送镜像"
        echo ""
        echo "下一步:"
        echo "  docker push host.docker.internal:5000/ubuntu-noble:latest"
    else
        echo "⚠️  配置正确，但 registry 未运行"
        echo ""
        echo "启动 registry:"
        echo "  docker start local-registry"
    fi
else
    echo "❌ 配置可能未生效"
    echo ""
    echo "请确保:"
    echo "1. Docker Desktop 已重启（Apply & Restart）"
    echo "2. 配置已保存"
    echo "3. 运行 'docker info' 查看完整配置"
fi

