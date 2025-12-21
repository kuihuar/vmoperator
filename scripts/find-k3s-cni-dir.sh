#!/bin/bash

# 查找 k3s CNI 配置目录

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "查找 k3s CNI 配置目录"
echo_info "=========================================="
echo ""

CNI_DIRS=()

# 方法 1: 尝试常见路径
echo_info "方法 1: 检查常见路径"
echo ""

COMMON_PATHS=(
    "/var/lib/rancher/k3s/agent/etc/cni/net.d"
    "/etc/cni/net.d"
    "/var/lib/rancher/k3s/server/manifests"
)

for path in "${COMMON_PATHS[@]}"; do
    if [ -d "$path" ]; then
        CONF_FILES=$(sudo find "$path" -maxdepth 1 -name "*.conf*" -o -name "*.conflist" 2>/dev/null | wc -l)
        if [ "$CONF_FILES" -gt 0 ] || [ -f "$path"/*.conf* ] 2>/dev/null; then
            echo_info "  ✓ 找到: $path"
            echo "    包含配置文件: $(sudo ls -1 "$path"/*.conf* 2>/dev/null | wc -l) 个"
            CNI_DIRS+=("$path")
        else
            echo_warn "  ⚠️  目录存在但无配置文件: $path"
        fi
    else
        echo_warn "  ✗ 不存在: $path"
    fi
done

# 方法 2: 从 k3s 服务配置获取
echo ""
echo_info "方法 2: 从 k3s 服务配置获取"
echo ""

if [ -f "/etc/systemd/system/k3s.service" ]; then
    echo_info "  检查 k3s.service..."
    
    # 查找 data-dir
    DATA_DIR=$(sudo grep -oP '--data-dir\s+\K[^\s]+' /etc/systemd/system/k3s.service 2>/dev/null || \
               sudo grep -oP '--data-dir=\K[^\s]+' /etc/systemd/system/k3s.service 2>/dev/null || echo "")
    
    if [ -n "$DATA_DIR" ]; then
        TEST_PATH="$DATA_DIR/agent/etc/cni/net.d"
        if [ -d "$TEST_PATH" ]; then
            echo_info "  ✓ 从 data-dir 找到: $TEST_PATH"
            CNI_DIRS+=("$TEST_PATH")
        else
            echo_warn "  ⚠️  data-dir 存在但 CNI 目录不存在: $TEST_PATH"
        fi
        echo_info "    data-dir: $DATA_DIR"
    else
        echo_warn "  ⚠️  未找到 --data-dir 参数（使用默认路径）"
    fi
else
    echo_warn "  ⚠️  k3s.service 文件不存在"
fi

# 方法 3: 从运行的 Multus Pod 获取
echo ""
echo_info "方法 3: 从运行的 Multus Pod 获取挂载信息"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Multus Pod: $MULTUS_POD"
    
    # 获取挂载的主机路径
    HOST_PATH=$(kubectl get pod -n kube-system "$MULTUS_POD" -o jsonpath='{.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
    MOUNT_PATH=$(kubectl get pod -n kube-system "$MULTUS_POD" -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")
    
    if [ -n "$HOST_PATH" ]; then
        echo_info "  ✓ 从 Pod 挂载找到主机路径: $HOST_PATH"
        echo_info "    Pod 内挂载点: $MOUNT_PATH"
        if [ -d "$HOST_PATH" ]; then
            CNI_DIRS+=("$HOST_PATH")
        fi
    else
        echo_warn "  ⚠️  无法从 Pod 获取挂载路径"
    fi
else
    echo_warn "  ⚠️  未找到运行中的 Multus Pod"
fi

# 方法 4: 搜索文件系统
echo ""
echo_info "方法 4: 搜索文件系统中的 CNI 配置文件"
echo ""

echo_info "  搜索 CNI 配置文件（可能需要一些时间）..."
SEARCH_RESULTS=$(sudo find /var/lib/rancher -type f \( -name "*.conf" -o -name "*.conflist" \) 2>/dev/null | grep -E "(cni|net\.d)" | head -5 || echo "")

if [ -n "$SEARCH_RESULTS" ]; then
    echo_info "  找到的文件："
    while IFS= read -r file; do
        DIR=$(dirname "$file")
        echo_info "    文件: $file"
        echo_info "    目录: $DIR"
        if [[ ! " ${CNI_DIRS[@]} " =~ " ${DIR} " ]]; then
            CNI_DIRS+=("$DIR")
        fi
    done <<< "$SEARCH_RESULTS"
else
    echo_warn "  ⚠️  未找到 CNI 配置文件"
fi

# 方法 5: 检查 k3s 数据目录结构
echo ""
echo_info "方法 5: 检查 k3s 数据目录结构"
echo ""

if [ -d "/var/lib/rancher/k3s" ]; then
    echo_info "  k3s 目录结构:"
    sudo find /var/lib/rancher/k3s -type d -name "net.d" -o -name "cni" 2>/dev/null | head -10 | while read dir; do
        echo_info "    $dir"
        if [ -d "$dir" ] && [ -n "$(sudo ls -A "$dir"/*.conf* 2>/dev/null)" ]; then
            CNI_DIRS+=("$dir")
        fi
    done
fi

# 总结
echo ""
echo_info "=========================================="
echo_info "查找结果"
echo_info "=========================================="
echo ""

if [ ${#CNI_DIRS[@]} -eq 0 ]; then
    echo_error "  ✗ 未找到 CNI 配置目录"
    echo ""
    echo_warn "可能的解决方法："
    echo "  1. 检查 k3s 是否正常运行: sudo systemctl status k3s"
    echo "  2. 手动查找: sudo find /var/lib/rancher -type d -name 'net.d' 2>/dev/null"
    echo "  3. 检查 k3s 日志: sudo journalctl -u k3s -n 50 | grep -i cni"
    exit 1
else
    # 去重
    UNIQUE_DIRS=($(printf '%s\n' "${CNI_DIRS[@]}" | sort -u))
    
    echo_info "  找到 ${#UNIQUE_DIRS[@]} 个可能的 CNI 配置目录："
    echo ""
    for i in "${!UNIQUE_DIRS[@]}"; do
        DIR="${UNIQUE_DIRS[$i]}"
        echo_info "  [$((i+1))] $DIR"
        
        # 显示目录内容
        echo "     文件列表:"
        sudo ls -lh "$DIR"/*.conf* 2>/dev/null | awk '{print "        "$9" ("$5")"}' || echo "        无配置文件"
        echo ""
    done
    
    # 推荐使用的目录（通常第一个是正确的）
    RECOMMENDED="${UNIQUE_DIRS[0]}"
    echo_info "  推荐使用的目录: $RECOMMENDED"
    echo ""
    echo_info "  使用以下命令创建 Multus 配置："
    echo "    sudo mkdir -p '$RECOMMENDED/multus.d'"
    echo "    sudo tee '$RECOMMENDED/multus.d/daemon-config.json' > /dev/null <<'EOF'"
    echo "{"
    echo "  \"binDir\": \"/opt/cni/bin\","
    echo "  \"confDir\": \"/etc/cni/net.d\","
    echo "  \"cniVersion\": \"0.3.1\","
    echo "  \"logLevel\": \"verbose\","
    echo "  \"logFile\": \"/var/log/multus.log\""
    echo "}"
    echo "EOF"
    echo "    sudo chmod 644 '$RECOMMENDED/multus.d/daemon-config.json'"
fi

echo ""

