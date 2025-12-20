#!/bin/bash

echo "检查本地 registry 状态..."

# 检查容器是否存在
if docker ps -a | grep -q local-registry; then
    echo "✅ local-registry 容器已存在"
    
    # 检查是否运行中
    if docker ps | grep -q local-registry; then
        echo "✅ local-registry 正在运行"
        echo ""
        echo "容器信息:"
        docker ps | grep local-registry
        echo ""
        echo "可以直接使用！"
    else
        echo "⚠️  local-registry 已停止，正在启动..."
        docker start local-registry
        sleep 2
        if docker ps | grep -q local-registry; then
            echo "✅ local-registry 已启动"
        else
            echo "❌ 启动失败，尝试重新创建..."
            docker rm local-registry
            docker run -d -p 5000:5000 --name local-registry registry:2
            sleep 2
            if docker ps | grep -q local-registry; then
                echo "✅ local-registry 已重新创建并启动"
            else
                echo "❌ 创建失败，请检查 Docker 状态"
                exit 1
            fi
        fi
    fi
else
    echo "📦 创建新的 local-registry 容器..."
    docker run -d -p 5000:5000 --name local-registry registry:2
    sleep 2
    if docker ps | grep -q local-registry; then
        echo "✅ local-registry 已创建并启动"
    else
        echo "❌ 创建失败，请检查 Docker 状态"
        exit 1
    fi
fi

echo ""
echo "验证 registry 是否可访问..."
if curl -s http://localhost:5000/v2/_catalog > /dev/null 2>&1; then
    echo "✅ Registry 可访问"
    echo ""
    echo "当前镜像列表:"
    curl -s http://localhost:5000/v2/_catalog | jq . 2>/dev/null || curl -s http://localhost:5000/v2/_catalog
else
    echo "⚠️  Registry 无法访问，但容器正在运行"
    echo "   可能需要等待几秒钟让 registry 完全启动"
fi

echo ""
echo "下一步:"
echo "1. 标记镜像: docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest"
echo "2. 推送镜像: docker push host.docker.internal:5000/ubuntu-noble:latest"

