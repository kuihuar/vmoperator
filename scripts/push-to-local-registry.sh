#!/bin/bash

# 配置
SOURCE_IMAGE="novasphere/ubuntu-noble:latest"
REGISTRY_IMAGE="host.docker.internal:5000/ubuntu-noble:latest"
LOCALHOST_IMAGE="localhost:5000/ubuntu-noble:latest"

echo "📦 推送镜像到本地 registry"
echo ""

# 1. 检查源镜像是否存在
echo "1. 检查源镜像..."
if ! docker images | grep -q "novasphere/ubuntu-noble"; then
    echo "❌ 错误: 找不到镜像 novasphere/ubuntu-noble"
    echo ""
    echo "可用的镜像:"
    docker images | head -10
    exit 1
fi

echo "✅ 找到镜像:"
docker images | grep "novasphere/ubuntu-noble"
echo ""

# 2. 检查本地 registry 是否运行
echo "2. 检查本地 registry..."
if ! docker ps | grep -q local-registry; then
    echo "⚠️  本地 registry 未运行，正在启动..."
    if docker ps -a | grep -q local-registry; then
        docker start local-registry
    else
        docker run -d -p 5000:5000 --name local-registry registry:2
    fi
    sleep 2
fi

if docker ps | grep -q local-registry; then
    echo "✅ 本地 registry 正在运行"
else
    echo "❌ 无法启动本地 registry"
    exit 1
fi
echo ""

# 3. 标记镜像（两个版本）
echo "3. 标记镜像..."
echo "   源镜像: $SOURCE_IMAGE"
echo "   标记为: $LOCALHOST_IMAGE (用于推送)"
echo "   标记为: $REGISTRY_IMAGE (用于 Kubernetes)"
docker tag "$SOURCE_IMAGE" "$LOCALHOST_IMAGE"
docker tag "$SOURCE_IMAGE" "$REGISTRY_IMAGE"
echo "✅ 镜像已标记"
echo ""

# 4. 检查 Docker 配置
echo "4. 检查 Docker 不安全仓库配置..."
if docker info 2>/dev/null | grep -q "host.docker.internal:5000\|localhost:5000"; then
    echo "✅ 已配置不安全仓库"
else
    echo "⚠️  警告: 可能未配置不安全仓库"
    echo "   如果推送失败，请配置 Docker Desktop:"
    echo "   Settings → Docker Engine → 添加:"
    echo '   "insecure-registries": ["localhost:5000", "host.docker.internal:5000"]'
    echo ""
fi

# 5. 推送镜像（先尝试 localhost，因为宿主机上更可靠）
echo "5. 推送镜像到本地 registry..."
echo "   📝 说明:"
echo "      - 推送时使用 localhost:5000（在宿主机上更可靠）"
echo "      - 拉取时使用 host.docker.internal:5000（Kubernetes Pod 需要）"
echo ""

PUSH_SUCCESS=false

# 先尝试推送 localhost 版本
echo "   尝试推送 localhost:5000 版本..."
if docker push "$LOCALHOST_IMAGE"; then
    echo "   ✅ localhost 版本推送成功"
    PUSH_SUCCESS=true
    
    # 如果 localhost 成功，也推送 host.docker.internal 版本（确保 Kubernetes 可以拉取）
    echo "   推送 host.docker.internal:5000 版本（用于 Kubernetes）..."
    if docker push "$REGISTRY_IMAGE"; then
        echo "   ✅ host.docker.internal 版本推送成功"
    else
        echo "   ⚠️  host.docker.internal 推送失败，但 localhost 版本已成功"
        echo "   ℹ️  这通常不影响使用，因为镜像已经在 registry 中"
    fi
else
    echo "   ⚠️  localhost 推送失败，尝试 host.docker.internal..."
    if docker push "$REGISTRY_IMAGE"; then
        echo "   ✅ host.docker.internal 版本推送成功"
        PUSH_SUCCESS=true
    fi
fi

if [ "$PUSH_SUCCESS" = true ]; then
    echo ""
    echo "✅ 推送成功！"
    echo ""
    
    # 6. 验证
    echo "6. 验证镜像..."
    if curl -s http://localhost:5000/v2/_catalog | grep -q ubuntu-noble; then
        echo "✅ 镜像已在 registry 中"
        echo ""
        echo "当前 registry 中的镜像:"
        curl -s http://localhost:5000/v2/_catalog | jq . 2>/dev/null || curl -s http://localhost:5000/v2/_catalog
        echo ""
        echo "✅ 完成！"
        echo ""
        echo "📝 重要说明:"
        echo "   - 推送时使用: localhost:5000（在宿主机上）"
        echo "   - 拉取时使用: host.docker.internal:5000（在 Kubernetes Pod 中）"
        echo ""
        echo "在 Wukong 中使用:"
        echo "  image: \"docker://$REGISTRY_IMAGE\""
        echo "  （Kubernetes Pod 会使用 host.docker.internal:5000 拉取）"
    else
        echo "⚠️  镜像可能未正确推送，请检查 registry"
    fi
else
    echo ""
    echo "❌ 推送失败"
    echo ""
    echo "可能的原因:"
    echo "1. Docker Desktop 未配置不安全仓库"
    echo "   解决: Settings → Docker Engine → 添加 insecure-registries"
    echo ""
    echo "2. Registry 未运行"
    echo "   解决: docker start local-registry"
    echo ""
    echo "3. 网络问题"
    echo "   解决: 检查防火墙和网络设置"
    exit 1
fi
