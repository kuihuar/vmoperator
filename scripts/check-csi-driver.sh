#!/bin/bash

# 检查 CSI Driver 状态

echo "=== 检查 CSI Driver 状态 ==="
echo ""

# 1. 检查 CSI Driver 对象
echo "1. 检查 CSI Driver 对象..."
kubectl get csidriver 2>/dev/null
if [ $? -eq 0 ]; then
    CSIDRIVER_COUNT=$(kubectl get csidriver --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$CSIDRIVER_COUNT" -gt 0 ]; then
        echo "✓ CSI Driver 存在 ($CSIDRIVER_COUNT 个)"
        kubectl get csidriver -o wide
    else
        echo "❌ CSI Driver 不存在"
    fi
else
    echo "❌ 无法获取 CSI Driver（可能 API 不支持）"
fi
echo ""

# 2. 检查 CSI 相关 Pods
echo "2. 检查 CSI 相关 Pods..."
CSI_PODS=$(kubectl get pods -n longhorn-system -o name 2>/dev/null | grep -E "csi|driver" || true)
if [ -n "$CSI_PODS" ]; then
    echo "找到 CSI 相关 Pods:"
    kubectl get pods -n longhorn-system | grep -E "csi|driver"
    echo ""
    
    # 检查每个 Pod 的状态
    echo "详细状态:"
    for pod in $CSI_PODS; do
        POD_NAME=$(echo $pod | cut -d'/' -f2)
        STATUS=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
        READY=$(kubectl get pod -n longhorn-system "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
        echo "  $POD_NAME: $STATUS (Ready: $READY)"
    done
else
    echo "❌ 没有找到 CSI 相关 Pods"
fi
echo ""

# 3. 检查 longhorn-driver-deployer
echo "3. 检查 longhorn-driver-deployer..."
DRIVER_DEPLOYER=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o name 2>/dev/null | head -1)
if [ -n "$DRIVER_DEPLOYER" ]; then
    DEPLOYER_NAME=$(echo $DRIVER_DEPLOYER | cut -d'/' -f2)
    DEPLOYER_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Driver Deployer: $DEPLOYER_NAME"
    echo "状态: $DEPLOYER_STATUS"
    echo ""
    
    # 检查 Init Containers
    INIT_COUNT=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
    if [ "$INIT_COUNT" -gt 0 ]; then
        echo "Init Containers ($INIT_COUNT 个):"
        for init in $(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null); do
            INIT_STATUS=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath="{.status.initContainerStatuses[?(@.name=='$init')].ready}" 2>/dev/null)
            INIT_STATE=$(kubectl get pod -n longhorn-system "$DEPLOYER_NAME" -o jsonpath="{.status.initContainerStatuses[?(@.name=='$init')].state}" 2>/dev/null)
            echo "  $init: Ready=$INIT_STATUS, State=$INIT_STATE"
        done
    fi
    
    # 如果卡住，显示日志
    if [ "$DEPLOYER_STATUS" != "Running" ] && [ "$DEPLOYER_STATUS" != "Succeeded" ]; then
        echo ""
        echo "⚠️  Driver Deployer 未完成，查看日志:"
        kubectl logs -n longhorn-system "$DEPLOYER_NAME" --all-containers=true --tail=10 2>&1 | tail -10
    fi
else
    echo "❌ longhorn-driver-deployer 不存在"
fi
echo ""

# 4. 检查 CSI 组件部署
echo "4. 检查 CSI 组件部署..."
echo "CSI Attacher:"
kubectl get deployment -n longhorn-system longhorn-csi-attacher 2>/dev/null && \
    kubectl get deployment -n longhorn-system longhorn-csi-attacher -o jsonpath='{.status.readyReplicas}/{.spec.replicas} ready' && echo "" || echo "  ❌ 不存在"
echo ""

echo "CSI Provisioner:"
kubectl get deployment -n longhorn-system longhorn-csi-provisioner 2>/dev/null && \
    kubectl get deployment -n longhorn-system longhorn-csi-provisioner -o jsonpath='{.status.readyReplicas}/{.spec.replicas} ready' && echo "" || echo "  ❌ 不存在"
echo ""

echo "CSI Resizer:"
kubectl get deployment -n longhorn-system longhorn-csi-resizer 2>/dev/null && \
    kubectl get deployment -n longhorn-system longhorn-csi-resizer -o jsonpath='{.status.readyReplicas}/{.spec.replicas} ready' && echo "" || echo "  ❌ 不存在"
echo ""

echo "CSI Plugin (DaemonSet):"
kubectl get daemonset -n longhorn-system longhorn-csi-plugin 2>/dev/null && \
    kubectl get daemonset -n longhorn-system longhorn-csi-plugin -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled} ready' && echo "" || echo "  ❌ 不存在"
echo ""

# 5. 总结
echo "=== 总结 ==="
echo ""

CSIDRIVER_EXISTS=$(kubectl get csidriver driver.longhorn.io 2>/dev/null && echo "yes" || echo "no")
CSI_PODS_EXIST=$(kubectl get pods -n longhorn-system | grep -q "csi" && echo "yes" || echo "no")
DRIVER_DEPLOYER_EXISTS=$(kubectl get pods -n longhorn-system | grep -q "driver-deployer" && echo "yes" || echo "no")

if [ "$CSIDRIVER_EXISTS" = "yes" ] && [ "$CSI_PODS_EXIST" = "yes" ]; then
    echo "✅ CSI Driver 已安装并运行"
    echo ""
    echo "如果 PVC 仍然 Pending，可能原因:"
    echo "  1. Longhorn Node 没有磁盘配置（最常见）"
    echo "  2. 存储空间不足"
    echo "  3. 网络问题"
    echo ""
    echo "检查:"
    echo "  ./scripts/diagnose-pvc-pending.sh <pvc-name>"
elif [ "$DRIVER_DEPLOYER_EXISTS" = "yes" ]; then
    echo "⚠️  CSI Driver 未安装，但 driver-deployer 存在"
    echo ""
    echo "可能原因:"
    echo "  1. driver-deployer 还在运行中（等待完成）"
    echo "  2. driver-deployer 卡住（需要重启）"
    echo ""
    echo "检查 driver-deployer 状态:"
    echo "  kubectl get pods -n longhorn-system | grep driver-deployer"
    echo "  kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true"
    echo ""
    echo "如果卡住，重启:"
    echo "  kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
else
    echo "❌ CSI Driver 未安装，且 driver-deployer 不存在"
    echo ""
    echo "可能原因:"
    echo "  1. Longhorn 安装不完整"
    echo "  2. Longhorn Manager 未就绪"
    echo ""
    echo "检查 Longhorn 状态:"
    echo "  kubectl get pods -n longhorn-system"
    echo "  ./scripts/check-longhorn-status.sh"
fi

echo ""
echo "=== 完成 ==="

