#!/bin/bash

# 修复 Multus 在 k3s 环境中的配置问题

echo "=== 修复 Multus 在 k3s 环境中的配置 ==="

# 1. 检查 k3s CNI 配置
echo -e "\n1. 检查 k3s CNI 配置..."
echo "k3s CNI 配置目录: /var/lib/rancher/k3s/agent/etc/cni/net.d/"
if [ -d /var/lib/rancher/k3s/agent/etc/cni/net.d ]; then
    echo "✓ 目录存在"
    echo "配置文件:"
    sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
    echo ""
    echo "配置文件内容:"
    sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf 2>/dev/null | head -20
else
    echo "❌ 目录不存在"
    exit 1
fi

# 2. 检查 Multus DaemonSet
echo -e "\n2. 检查 Multus DaemonSet..."
if kubectl get daemonset -n kube-system kube-multus-ds 2>/dev/null | grep -q multus; then
    echo "Multus DaemonSet 存在:"
    kubectl get daemonset -n kube-system kube-multus-ds
    echo ""
    echo "检查 Pods:"
    kubectl get pods -n kube-system -l app=multus
else
    echo "⚠️  Multus DaemonSet 不存在"
    echo "检查是否有其他名称的 Multus:"
    kubectl get daemonset -n kube-system | grep -i multus
fi

# 3. 检查 Multus Pod 的挂载
echo -e "\n3. 检查 Multus Pod 的挂载..."
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MULTUS_POD" ]; then
    echo "Multus Pod: $MULTUS_POD"
    echo ""
    echo "检查 volumeMounts:"
    kubectl get pod -n kube-system "$MULTUS_POD" -o yaml | grep -A 10 "volumeMounts:" | head -20
    echo ""
    echo "检查 volumes:"
    kubectl get pod -n kube-system "$MULTUS_POD" -o yaml | grep -A 10 "volumes:" | head -20
else
    echo "⚠️  未找到 Multus Pod"
fi

# 4. 检查 Multus DaemonSet 的配置
echo -e "\n4. 检查 Multus DaemonSet 的配置..."
if kubectl get daemonset -n kube-system kube-multus-ds 2>/dev/null | grep -q multus; then
    echo "检查 volumeMounts:"
    kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 15 "volumeMounts:" | head -25
    echo ""
    echo "检查 volumes:"
    kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 15 "volumes:" | head -25
fi

# 5. 修复方案：更新 Multus DaemonSet
echo -e "\n5. 修复方案：更新 Multus DaemonSet..."
echo "k3s 的 CNI 配置在: /var/lib/rancher/k3s/agent/etc/cni/net.d/"
echo "需要确保 Multus 能够访问这个目录"
echo ""

read -p "是否更新 Multus DaemonSet 以使用正确的 k3s CNI 路径？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "更新 Multus DaemonSet..."
    
    # 备份当前配置
    kubectl get daemonset -n kube-system kube-multus-ds -o yaml > /tmp/multus-ds-backup.yaml
    echo "✓ 已备份到: /tmp/multus-ds-backup.yaml"
    
    # 更新 DaemonSet
    kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
      {
        "op": "replace",
        "path": "/spec/template/spec/containers/0/volumeMounts",
        "value": [
          {
            "name": "cni",
            "mountPath": "/host/etc/cni/net.d"
          },
          {
            "name": "cnibin",
            "mountPath": "/host/opt/cni/bin"
          },
          {
            "name": "multus-cni-config",
            "mountPath": "/host/etc/cni/net.d/00-multus.conf",
            "subPath": "00-multus.conf"
          }
        ]
      },
      {
        "op": "replace",
        "path": "/spec/template/spec/volumes",
        "value": [
          {
            "name": "cni",
            "hostPath": {
              "path": "/var/lib/rancher/k3s/agent/etc/cni/net.d",
              "type": "Directory"
            }
          },
          {
            "name": "cnibin",
            "hostPath": {
              "path": "/var/lib/rancher/k3s/data/current/bin",
              "type": "Directory"
            }
          },
          {
            "name": "multus-cni-config",
            "configMap": {
              "name": "multus-cni-config"
            }
          }
        ]
      }
    ]' 2>&1 | head -10
    
    echo ""
    echo "等待 Pod 重启..."
    sleep 10
    
    # 删除 Pod 以触发重启
    kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
    sleep 10
    
    echo "检查新 Pod 状态:"
    kubectl get pods -n kube-system -l app=multus
else
    echo "跳过自动修复"
    echo ""
    echo "手动修复步骤："
    echo "  1. 编辑 Multus DaemonSet:"
    echo "     kubectl edit daemonset -n kube-system kube-multus-ds"
    echo ""
    echo "  2. 更新 volumeMounts，将 /host/etc/cni/net.d 挂载到:"
    echo "     /var/lib/rancher/k3s/agent/etc/cni/net.d"
    echo ""
    echo "  3. 更新 volumes，使用正确的 hostPath:"
    echo "     path: /var/lib/rancher/k3s/agent/etc/cni/net.d"
fi

# 6. 检查修复后的状态
echo -e "\n6. 检查修复后的状态..."
sleep 5
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MULTUS_POD" ]; then
    echo "检查 Pod 日志:"
    kubectl logs -n kube-system "$MULTUS_POD" --tail=20 | grep -E "error|failed|success|ready" || kubectl logs -n kube-system "$MULTUS_POD" --tail=10
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果问题仍然存在，检查："
echo "  1. k3s CNI 配置: sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/"
echo "  2. Multus Pod 日志: kubectl logs -n kube-system -l app=multus"
echo "  3. Multus Pod 描述: kubectl describe pod -n kube-system -l app=multus"

