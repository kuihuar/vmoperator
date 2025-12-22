#!/bin/bash

# 检查 Multus NAD 配置

echo "检查 Multus NetworkAttachmentDefinition..."
echo ""

echo "1. 检查 kube-system 中的 NAD:"
kubectl get networkattachmentdefinition -n kube-system

echo ""
echo "2. 检查 flannel NAD 详情:"
kubectl get networkattachmentdefinition -n kube-system flannel -o yaml 2>/dev/null || echo "flannel NAD 不存在"

echo ""
echo "3. 检查 Multus 配置:"
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | jq '.clusterNetwork'

echo ""
echo "4. 检查 k3s CNI 配置文件:"
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/*.{conf,conflist} 2>/dev/null | grep -v multus

