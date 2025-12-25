#!/bin/bash

# 验证 k3s 安装脚本是否正确传递参数

echo "检查安装脚本中的参数构建..."
echo ""

# 模拟脚本执行
SERVER_IP="${SERVER_IP:-192.168.1.141}"
CLUSTER_CIDR="${CLUSTER_CIDR:-10.42.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.43.0.0/16}"
DISABLE_SERVICELB="${DISABLE_SERVICELB:-false}"

K3S_SERVER_ARGS="server --tls-san ${SERVER_IP} --cluster-cidr ${CLUSTER_CIDR} --service-cidr ${SERVICE_CIDR}"

if [[ "${DISABLE_SERVICELB}" =~ ^[Tt]rue$ ]]; then
    K3S_SERVER_ARGS="${K3S_SERVER_ARGS} --disable servicelb"
fi

echo "构建的 K3S_SERVER_ARGS:"
echo "${K3S_SERVER_ARGS}"
echo ""

echo "应该传递给 k3s 安装脚本的命令："
echo "INSTALL_K3S_EXEC=\"${K3S_SERVER_ARGS}\""
echo ""

echo "实际 systemd 配置中的 ExecStart："
sudo systemctl cat k3s | grep -A 10 "ExecStart" | head -15

echo ""
echo "对比分析："
EXPECTED_ARGS=("--cluster-cidr" "--service-cidr")
for arg in "${EXPECTED_ARGS[@]}"; do
    if sudo systemctl cat k3s 2>/dev/null | grep -q "${arg}"; then
        echo "  ✓ 找到 ${arg}"
    else
        echo "  ✗ 未找到 ${arg}"
    fi
done

