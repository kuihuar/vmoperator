#!/bin/bash

# 不进入 Pod 检查 DNS 问题的方法

echo "=========================================="
echo "检查 DNS 198.18.x.x 问题（不进入 Pod）"
echo "=========================================="
echo ""

# 1. 检查 Service 的实际 ClusterIP
echo "1. 检查 kubernetes Service 的实际 ClusterIP："
kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' && echo ""
echo "  应该解析到这个 IP，而不是 198.18.x.x"
echo ""

# 2. 检查 Endpoints
echo "2. 检查 kubernetes Service 的 Endpoints："
kubectl get endpoints kubernetes -n default -o yaml | grep -A 10 "addresses:" | head -15
echo ""

# 3. 检查 k3s manifests（可能包含 DNS 相关配置）
echo "3. 检查 k3s manifests 目录："
if [ -d /var/lib/rancher/k3s/server/manifests ]; then
    echo "  manifests 目录内容："
    sudo ls -la /var/lib/rancher/k3s/server/manifests/ 2>/dev/null | sed 's/^/    /' || echo "    无法访问"
    
    # 检查是否有 coredns 相关的 manifest
    for file in $(sudo ls /var/lib/rancher/k3s/server/manifests/ 2>/dev/null); do
        if echo "${file}" | grep -qiE "coredns|dns"; then
            echo ""
            echo "  发现 DNS 相关文件: ${file}"
            sudo cat /var/lib/rancher/k3s/server/manifests/${file} 2>/dev/null | grep -E "198\.18|hosts|rewrite" | sed 's/^/    /' || echo "    未发现相关配置"
        fi
    done
else
    echo "  manifests 目录不存在"
fi
echo ""

# 4. 检查 k3s 配置目录
echo "4. 检查 k3s 配置目录："
if [ -d /etc/rancher/k3s ]; then
    echo "  /etc/rancher/k3s 目录内容："
    sudo ls -la /etc/rancher/k3s/ 2>/dev/null | sed 's/^/    /' || echo "    无法访问"
    
    if [ -f /etc/rancher/k3s/config.yaml ]; then
        echo ""
        echo "  config.yaml 内容："
        sudo cat /etc/rancher/k3s/config.yaml 2>/dev/null | sed 's/^/    /' || echo "    无法读取"
    fi
else
    echo "  配置目录不存在"
fi
echo ""

# 5. 检查是否有 LoadBalancer Service
echo "5. 检查 LoadBalancer 类型的 Service："
kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.type}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' | grep "LoadBalancer" | sed 's/^/  /' || echo "  没有 LoadBalancer 类型的 Service"
echo ""

# 6. 总结和建议
echo "=========================================="
echo "总结和建议"
echo "=========================================="
echo ""
echo "从 ConfigMap 看，CoreDNS 配置是正常的，没有 198.18.x.x 的配置。"
echo ""
echo "可能的原因："
echo "  1. k3s 的 DNS 实现有特殊行为（即使禁用了 ServiceLB）"
echo "  2. 需要检查 k3s manifests 目录中的配置"
echo "  3. 可能是 k3s 版本的已知问题"
echo ""
echo "建议："
echo "  1. 检查 k3s GitHub issues 中是否有类似问题"
echo "  2. 尝试使用其他 DNS 解决方案（如替换 CoreDNS）"
echo "  3. 如果只是 DNS 解析问题，但实际连接正常，可以暂时忽略"
echo "  4. 检查 Longhorn 等组件是否能正常工作（可能不受影响）"
echo ""

