#!/bin/bash

# 检查代理配置

echo "=== 检查代理配置 ==="

# 1. 检查环境变量
echo -e "\n1. 检查环境变量..."
echo "HTTP_PROXY: ${HTTP_PROXY:-未设置}"
echo "HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
echo "http_proxy: ${http_proxy:-未设置}"
echo "https_proxy: ${https_proxy:-未设置}"
echo "NO_PROXY: ${NO_PROXY:-未设置}"
echo "no_proxy: ${no_proxy:-未设置}"

# 2. 检查 /etc/environment
echo -e "\n2. 检查 /etc/environment..."
if [ -f /etc/environment ]; then
    if grep -qi "proxy" /etc/environment; then
        echo "⚠️  发现代理配置:"
        grep -i "proxy" /etc/environment
    else
        echo "✓ 未发现代理配置"
    fi
else
    echo "文件不存在"
fi

# 3. 检查 k3s systemd 服务
echo -e "\n3. 检查 k3s systemd 服务..."
if [ -f /etc/systemd/system/k3s.service ]; then
    if sudo grep -qi "proxy\|Environment" /etc/systemd/system/k3s.service; then
        echo "⚠️  发现环境变量配置:"
        sudo grep -i "proxy\|Environment" /etc/systemd/system/k3s.service
    else
        echo "✓ 未发现代理配置"
    fi
else
    echo "服务文件不存在"
fi

# 检查 systemd override
if [ -d /etc/systemd/system/k3s.service.d ]; then
    echo "检查 systemd override 目录..."
    for f in /etc/systemd/system/k3s.service.d/*; do
        if [ -f "$f" ]; then
            echo "  文件: $f"
            if sudo grep -qi "proxy" "$f"; then
                echo "  ⚠️  发现代理配置:"
                sudo grep -i "proxy" "$f"
            fi
        fi
    done
fi

# 4. 检查 k3s 运行时环境变量
echo -e "\n4. 检查 k3s 运行时环境变量..."
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    echo "k3s 服务环境变量:"
    sudo systemctl show k3s | grep -i "proxy" || echo "  ✓ 未发现代理环境变量"
else
    echo "k3s 服务未运行"
fi

# 5. 检查 containerd 配置
echo -e "\n5. 检查 containerd 配置..."
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    if sudo grep -qi "proxy\|ustc" /var/lib/rancher/k3s/agent/etc/containerd/config.toml; then
        echo "⚠️  发现代理或旧镜像源配置:"
        sudo grep -i "proxy\|ustc" /var/lib/rancher/k3s/agent/etc/containerd/config.toml
    else
        echo "✓ 未发现代理配置"
    fi
else
    echo "配置文件不存在"
fi

# 6. 检查 shell 配置文件
echo -e "\n6. 检查 shell 配置文件..."
for file in ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc; do
    if [ -f "$file" ] && grep -qi "proxy" "$file"; then
        echo "⚠️  在 $file 中发现代理配置:"
        grep -i "proxy" "$file"
    fi
done

echo -e "\n=== 检查完成 ==="
echo ""
echo "如果发现代理配置指向 docker.mirrors.ustc.edu.cn，需要清理："
echo "  1. /etc/environment: sudo vim /etc/environment"
echo "  2. k3s systemd 服务: sudo systemctl edit k3s"
echo "  3. shell 配置文件: vim ~/.bashrc 等"
echo "  4. 清理后重启 k3s: sudo systemctl restart k3s"

