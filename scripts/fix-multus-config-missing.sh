#!/bin/bash

# 修复 Multus 配置文件缺失问题

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
echo_info "修复 Multus 配置文件缺失问题"
echo_info "=========================================="
echo ""

# 错误信息：open /etc/cni/net.d/multus.d/daemon-config.json: no such file or directory

# 1. 检测 k3s CNI 配置目录
echo_info "1. 检测 k3s CNI 配置目录"
echo ""

# 尝试多个可能的路径
POSSIBLE_PATHS=(
    "/var/lib/rancher/k3s/agent/etc/cni/net.d"
    "/etc/cni/net.d"
    "/var/lib/rancher/k3s/server/manifests"
)

K3S_CNI_DIR=""

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        # 检查是否包含 CNI 配置文件（通常是 .conf 或 .conflist 文件）
        if sudo ls "$path"/*.conf* 2>/dev/null | grep -q . || sudo ls "$path"/*.yaml 2>/dev/null | grep -q .; then
            K3S_CNI_DIR="$path"
            echo_info "  ✓ 找到 CNI 配置目录: $K3S_CNI_DIR"
            break
        fi
    fi
done

# 如果还是没找到，尝试从 k3s 进程或服务中获取
if [ -z "$K3S_CNI_DIR" ]; then
    echo_warn "  未在常见路径找到 CNI 配置目录，尝试其他方法..."
    
    # 检查 k3s 服务配置
    if [ -f "/etc/systemd/system/k3s.service" ]; then
        echo_info "  检查 k3s.service 中的配置..."
        K3S_DATA_DIR=$(sudo grep -oP '--data-dir \K[^\s]+' /etc/systemd/system/k3s.service 2>/dev/null || echo "")
        if [ -n "$K3S_DATA_DIR" ]; then
            TEST_PATH="$K3S_DATA_DIR/agent/etc/cni/net.d"
            if [ -d "$TEST_PATH" ]; then
                K3S_CNI_DIR="$TEST_PATH"
                echo_info "  ✓ 从 k3s.service 找到: $K3S_CNI_DIR"
            fi
        fi
    fi
    
    # 如果还是没找到，检查当前运行的 Pod 中的挂载
    if [ -z "$K3S_CNI_DIR" ]; then
        echo_warn "  检查运行中的 Pod 挂载信息..."
        MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$MULTUS_POD" ]; then
            MOUNT_PATH=$(kubectl get pod -n kube-system "$MULTUS_POD" -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")
            HOST_PATH=$(kubectl get pod -n kube-system "$MULTUS_POD" -o jsonpath='{.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
            if [ -n "$HOST_PATH" ] && [ -d "$HOST_PATH" ]; then
                K3S_CNI_DIR="$HOST_PATH"
                echo_info "  ✓ 从 Multus Pod 挂载信息找到: $K3S_CNI_DIR"
            fi
        fi
    fi
fi

# 如果仍然没找到，询问用户或尝试创建
if [ -z "$K3S_CNI_DIR" ]; then
    echo_error "  ✗ 无法自动检测 CNI 配置目录"
    echo ""
    echo_warn "请手动指定 CNI 配置目录路径："
    echo "  1. 查找 k3s 的 CNI 配置: sudo find /var/lib/rancher -name '*.conf*' -o -name '*.conflist' 2>/dev/null | head -5"
    echo "  2. 或检查 k3s 数据目录: sudo ls -la /var/lib/rancher/k3s/"
    echo "  3. 或运行: sudo systemctl status k3s | grep -i 'data-dir'"
    echo ""
    read -p "请输入 CNI 配置目录的完整路径（例如 /var/lib/rancher/k3s/agent/etc/cni/net.d）: " K3S_CNI_DIR
    
    if [ -z "$K3S_CNI_DIR" ] || [ ! -d "$K3S_CNI_DIR" ]; then
        echo_error "  路径无效或不存在，退出"
        exit 1
    fi
fi

echo_info "  使用 CNI 配置目录: $K3S_CNI_DIR"
echo_info "  目录内容:"
sudo ls -la "$K3S_CNI_DIR" 2>/dev/null | head -10 || echo_warn "    需要 sudo 权限查看"

# 2. 创建 multus.d 目录
echo ""
echo_info "2. 创建 multus.d 目录和配置文件"
echo ""

MULTUS_DIR="$K3S_CNI_DIR/multus.d"
echo_info "  Multus 配置目录: $MULTUS_DIR"

if [ ! -d "$MULTUS_DIR" ]; then
    echo_info "  创建目录: $MULTUS_DIR"
    if sudo mkdir -p "$MULTUS_DIR"; then
        echo_info "  ✓ 目录已创建"
    else
        echo_error "  ✗ 创建目录失败，可能需要检查权限"
        exit 1
    fi
else
    echo_info "  ✓ 目录已存在: $MULTUS_DIR"
fi

# 3. 创建 daemon-config.json 文件
echo ""
echo_info "3. 创建 daemon-config.json 配置文件"
echo ""

CONFIG_FILE="$MULTUS_DIR/daemon-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo_info "  创建配置文件: $CONFIG_FILE"
    
    # 创建默认配置
    sudo tee "$CONFIG_FILE" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "/etc/cni/net.d",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log"
}
EOF
    
    echo_info "  ✓ 配置文件已创建"
else
    echo_info "  ✓ 配置文件已存在: $CONFIG_FILE"
fi

# 4. 检查并创建 00-multus.conf（如果不存在）
echo ""
echo_info "4. 检查 Multus 主配置文件"
echo ""

MULTUS_CONF="$K3S_CNI_DIR/00-multus.conf"

if [ ! -f "$MULTUS_CONF" ]; then
    echo_warn "  ⚠️  Multus 主配置文件不存在，创建默认配置..."
    
    # 检查默认 CNI（通常是 Flannel）
    DEFAULT_CNI=$(ls "$K3S_CNI_DIR"/*.conf* 2>/dev/null | grep -v multus | head -1 || echo "")
    
    if [ -n "$DEFAULT_CNI" ]; then
        echo_info "  检测到默认 CNI 配置: $DEFAULT_CNI"
        DEFAULT_CNI_NAME=$(basename "$DEFAULT_CNI")
    else
        echo_warn "  未找到默认 CNI 配置，使用默认值"
        DEFAULT_CNI_NAME="10-flannel.conflist"
    fi
    
    # 创建 Multus 配置
    sudo tee "$MULTUS_CONF" > /dev/null <<EOF
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "capabilities": {
    "portMappings": true
  },
  "delegates": [
    {
      "cniVersion": "0.3.1",
      "name": "default",
      "type": "flannel"
    }
  ],
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig"
}
EOF
    
    echo_info "  ✓ Multus 主配置文件已创建"
else
    echo_info "  ✓ Multus 主配置文件已存在: $MULTUS_CONF"
fi

# 5. 设置正确的权限
echo ""
echo_info "5. 设置文件权限"
echo ""

sudo chmod 644 "$CONFIG_FILE" 2>/dev/null || true
sudo chmod 755 "$MULTUS_DIR" 2>/dev/null || true

echo_info "  ✓ 权限已设置"

# 6. 验证配置
echo ""
echo_info "6. 验证配置"
echo ""

if [ -f "$CONFIG_FILE" ]; then
    echo_info "  配置文件路径: $CONFIG_FILE"
    echo_info "  文件权限:"
    sudo ls -la "$CONFIG_FILE" | sed 's/^/    /'
    echo ""
    echo_info "  配置文件内容:"
    sudo cat "$CONFIG_FILE" | sed 's/^/    /'
    echo ""
    echo_info "  ✓ 配置文件验证通过"
else
    echo_error "  ✗ 配置文件验证失败: $CONFIG_FILE 不存在"
    echo_warn "  请检查："
    echo "    1. 目录权限: sudo ls -ld $MULTUS_DIR"
    echo "    2. 是否成功创建: sudo test -f $CONFIG_FILE && echo '存在' || echo '不存在'"
    exit 1
fi

# 6.1 确保 Multus Pod 能看到这个文件（检查 DaemonSet 挂载）
echo ""
echo_info "6.1 检查 Multus DaemonSet 挂载配置"
echo ""

MULTUS_DS=$(kubectl get daemonset -n kube-system kube-multus-ds -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_DS" ]; then
    DS_CNI_PATH=$(kubectl get $MULTUS_DS -n kube-system -o jsonpath='{.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
    
    if [ -n "$DS_CNI_PATH" ]; then
        if [ "$DS_CNI_PATH" = "$K3S_CNI_DIR" ]; then
            echo_info "  ✓ DaemonSet 挂载路径正确: $DS_CNI_PATH"
        else
            echo_warn "  ⚠️  DaemonSet 挂载路径 ($DS_CNI_PATH) 与检测到的路径 ($K3S_CNI_DIR) 不一致"
            echo_warn "  这可能导致 Multus 无法读取配置文件"
            echo_info "  建议运行: ./scripts/fix-multus-k3s.sh 来修复挂载路径"
        fi
    else
        echo_warn "  ⚠️  无法获取 DaemonSet 挂载路径"
    fi
else
    echo_warn "  ⚠️  未找到 Multus DaemonSet"
fi

# 7. 重启 Multus Pod
echo ""
echo_info "7. 重启 Multus Pod"
echo ""

MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$MULTUS_PODS" ]; then
    echo_info "  删除现有的 Multus Pod..."
    for pod in $MULTUS_PODS; do
        kubectl delete pod -n kube-system "$pod" --force --grace-period=0 2>/dev/null || true
        echo_info "    ✓ 已删除: $pod"
    done
    
    echo_info "  ✓ 等待 Pod 自动重新创建..."
    sleep 5
else
    echo_warn "  未找到 Multus Pod"
fi

# 8. 检查状态
echo ""
echo_info "8. 检查修复结果"
echo ""

sleep 10

echo_info "Multus Pod 状态:"
kubectl get pods -n kube-system -l app=multus 2>/dev/null || echo_warn "  未找到 Pod"

echo ""
echo_info "查看最新的 Multus 日志:"
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod: $MULTUS_POD"
    kubectl logs -n kube-system "$MULTUS_POD" --tail=20 2>&1 | head -15 || echo_warn "  无法获取日志"
else
    echo_warn "  等待 Pod 创建..."
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 仍然有问题，请检查："
echo "  1. Multus DaemonSet 的 volumeMounts 是否正确挂载了配置目录"
echo "  2. 运行: kubectl describe pod -n kube-system -l app=multus"
echo "  3. 查看日志: kubectl logs -n kube-system -l app=multus --tail=50"
echo ""

