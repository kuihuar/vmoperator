# 完整安装指南：k3s + KubeVirt + Multus CNI

本指南提供在 k3s 环境中完整安装 KubeVirt 和 Multus CNI 的详细步骤，所有配置均经过验证。

## 目录

1. [前置条件](#前置条件)
2. [步骤 1: 安装 k3s](#步骤-1-安装-k3s)
3. [步骤 2: 配置 kubeconfig](#步骤-2-配置-kubeconfig)
4. [步骤 3: 安装 KubeVirt](#步骤-3-安装-kubevirt)
5. [步骤 4: 安装 CDI](#步骤-4-安装-cdi)
6. [步骤 5: 安装 Multus CNI（k3s 专用配置）](#步骤-5-安装-multus-cni-k3s-专用配置)
7. [步骤 6: 验证所有组件](#步骤-6-验证所有组件)
8. [常见问题排查](#常见问题排查)

---

## 前置条件

### 硬件要求

- **CPU**: 支持虚拟化扩展（Intel VT-x / AMD-V）
- **内存**: 至少 8GB（推荐 16GB+）
- **存储**: 至少 50GB 可用空间
- **操作系统**: Linux (推荐 Ubuntu 20.04+) 或 macOS (用于开发)

### 软件要求

```bash
# 必需工具
- kubectl >= 1.24
- curl
- sudo 权限
```

---

## 步骤 1: 安装 k3s

### 1.1 快速安装

```bash
# 安装 k3s
curl -sfL https://get.k3s.io | sh -

# 检查状态
sudo systemctl status k3s
```

### 1.2 验证安装

```bash
# 使用 k3s 自带的 kubectl
sudo k3s kubectl get nodes

# 应该看到类似输出：
# NAME     STATUS   ROLES                  AGE   VERSION
# host1    Ready    control-plane,master   1m    v1.28.x+k3s1
```

---

## 步骤 2: 配置 kubeconfig

**重要**：为了在本地使用 `kubectl`，需要配置 kubeconfig。

### 2.1 复制 k3s kubeconfig 到用户目录

```bash
# 创建 .kube 目录
mkdir -p ~/.kube

# 复制 k3s kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# 如果 k3s.yaml 中的 server 地址是 127.0.0.1，需要修改为实际 IP
# 查看当前 server 地址
grep server ~/.kube/config

# 如果需要修改（例如改为节点 IP）
sed -i 's/127.0.0.1/你的节点IP/g' ~/.kube/config
```

### 2.2 或者使用环境变量

```bash
# 设置 KUBECONFIG 环境变量
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 验证连接
kubectl get nodes
```

---

## 步骤 3: 安装 KubeVirt

### 3.1 安装 KubeVirt Operator

```bash
# 设置版本（自动获取最新稳定版）
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 或者使用固定版本（推荐，更稳定）
export KUBEVIRT_VERSION=v1.2.0

# 安装 KubeVirt Operator
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

# 等待 Operator 就绪（约 1-2 分钟）
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s
```

### 3.2 安装 KubeVirt CR

```bash
# 安装 KubeVirt CR
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

# 等待 KubeVirt 就绪（约 2-3 分钟）
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s
```

### 3.3 配置 KubeVirt（k3s 环境）

在 k3s 环境中，如果硬件不支持 KVM，需要启用软件模拟：

```bash
# 启用软件模拟（如果硬件不支持 KVM）
kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

### 3.4 添加节点 Label

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 添加 label
kubectl label node $NODE_NAME kubevirt.io/schedulable=true --overwrite
```

### 3.5 验证 KubeVirt 安装

```bash
# 检查 Pods
kubectl get pods -n kubevirt

# 应该看到类似：
# NAME                               READY   STATUS    RESTARTS   AGE
# virt-operator-xxxxx                1/1     Running   0          2m
# virt-controller-xxxxx               1/1     Running   0          1m
# virt-handler-xxxxx                  1/1     Running   0          1m
# virt-api-xxxxx                      1/1     Running   0          1m

# 检查 KubeVirt CR
kubectl get kubevirt -n kubevirt

# 应该看到：
# NAME       AGE   PHASE
# kubevirt   2m    Deployed
```

---

## 步骤 4: 安装 CDI

CDI (Containerized Data Importer) 是 KubeVirt 的数据导入工具，必须先安装。

### 4.1 安装 CDI Operator

```bash
# 设置版本（自动获取最新稳定版）
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 或者使用固定版本
export CDI_VERSION=v1.62.0

# 安装 CDI Operator
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

# 等待 Operator 就绪
kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s
```

### 4.2 安装 CDI CR

```bash
# 安装 CDI CR
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 等待 CDI 就绪
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s
```

### 4.3 验证 CDI 安装

```bash
# 检查 Pods
kubectl get pods -n cdi

# 应该看到类似：
# NAME                               READY   STATUS    RESTARTS   AGE
# cdi-operator-xxxxx                 1/1     Running   0          2m
# cdi-apiserver-xxxxx                 1/1     Running   0          1m
# cdi-deployment-xxxxx                1/1     Running   0          1m
# cdi-uploadproxy-xxxxx               1/1     Running   0          1m
```

---

## 步骤 5: 安装 Multus CNI（k3s 专用配置）

**重要**：这是经过验证的 k3s 专用 Multus 配置，解决了路径重复问题。

### 5.1 下载官方 Multus DaemonSet

```bash
# 下载官方 Multus DaemonSet（thin plugin 模式）
curl -L -o /tmp/multus-daemonset.yml \
  https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
```

### 5.2 修改 DaemonSet 适配 k3s

k3s 使用自定义的 CNI 路径，需要修改 DaemonSet 的挂载配置和启动参数。

#### 5.2.1 修改 volumes 和 volumeMounts

使用 `sed` 或 `awk` 修改 YAML 文件：

```bash
# 备份原文件
cp /tmp/multus-daemonset.yml /tmp/multus-daemonset.yml.bak

# 使用 awk 修改 hostPath（只修改 path 值，保持 YAML 结构）
awk -v cni_conf="/var/lib/rancher/k3s/agent/etc/cni/net.d" \
    -v cni_bin="/var/lib/rancher/k3s/data/current/bin" '
/hostPath:/ {
    in_hostpath=1
    print
    next
}
in_hostpath && /path:/ {
    if (match($0, /path:.*\/etc\/cni\/net\.d/)) {
        print "        path: " cni_conf
    } else if (match($0, /path:.*\/opt\/cni\/bin/)) {
        print "        path: " cni_bin
    } else {
        print
    }
    in_hostpath=0
    next
}
{
    print
}
' /tmp/multus-daemonset.yml.bak > /tmp/multus-daemonset-k3s.yml
```

#### 5.2.2 修改容器启动参数（关键！）

这是**最关键的步骤**，必须修改容器的启动参数，避免路径重复问题：

```bash
# 修改容器 args，使用 Pod 内路径而不是主机路径
sed -i 's|--multus-autoconfig-dir=/host/var/lib/rancher/k3s/agent/var/lib/rancher/k3s/agent/etc/cni/net.d|--multus-autoconfig-dir=/host/etc/cni/net.d|g' /tmp/multus-daemonset-k3s.yml
sed -i 's|--cni-conf-dir=/host/var/lib/rancher/k3s/agent/var/lib/rancher/k3s/agent/etc/cni/net.d|--cni-conf-dir=/host/etc/cni/net.d|g' /tmp/multus-daemonset-k3s.yml

# 如果原文件没有这些参数，需要添加
# 检查是否已有这些参数
if ! grep -q "--multus-autoconfig-dir" /tmp/multus-daemonset-k3s.yml; then
    # 在 kube-multus 容器的 args 中添加
    sed -i '/name: kube-multus/,/volumeMounts:/ {
        /args:/a\
        - --multus-conf-file=auto\
        - --multus-autoconfig-dir=/host/etc/cni/net.d\
        - --cni-conf-dir=/host/etc/cni/net.d
    }' /tmp/multus-daemonset-k3s.yml
fi
```

### 5.3 使用已验证的 DaemonSet 配置（推荐）

为了避免手动修改出错，可以直接使用已验证的配置：

```bash
# 在项目目录中
cd /Users/jianfenliu/Workspace/vmoperator

# 使用已验证的配置
kubectl apply -f tmp/kube-multus-ds-clean.yaml
```

或者，如果你需要从头创建，可以使用以下完整配置：

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: multus
    name: multus
    tier: node
  name: kube-multus-ds
  namespace: kube-system
spec:
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      name: multus
  template:
    metadata:
      labels:
        app: multus
        name: multus
        tier: node
    spec:
      containers:
      - args:
        - --multus-conf-file=auto
        - --multus-autoconfig-dir=/host/etc/cni/net.d
        - --cni-conf-dir=/host/etc/cni/net.d
        command:
        - /thin_entrypoint
        image: ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot
        imagePullPolicy: IfNotPresent
        name: kube-multus
        resources:
          limits:
            cpu: 100m
            memory: 50Mi
          requests:
            cpu: 100m
            memory: 50Mi
        securityContext:
          privileged: true
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: FallbackToLogsOnError
        volumeMounts:
        - mountPath: /host/etc/cni/net.d
          name: cni
        - mountPath: /host/opt/cni/bin
          name: cnibin
        - mountPath: /host/etc/cni/net.d/multus.d
          name: multus-cfg
      dnsPolicy: ClusterFirst
      hostNetwork: true
      initContainers:
      - args:
        - --type
        - thin
        command:
        - /install_multus
        image: ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot
        imagePullPolicy: IfNotPresent
        name: install-multus-binary
        resources:
          requests:
            cpu: 10m
            memory: 15Mi
        securityContext:
          privileged: true
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: FallbackToLogsOnError
        volumeMounts:
        - mountPath: /host/opt/cni/bin
          mountPropagation: Bidirectional
          name: cnibin
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      serviceAccount: multus
      serviceAccountName: multus
      terminationGracePeriodSeconds: 10
      tolerations:
      - effect: NoSchedule
        operator: Exists
      - effect: NoExecute
        operator: Exists
      volumes:
      - hostPath:
          path: /var/lib/rancher/k3s/agent/etc/cni/net.d
          type: Directory
        name: cni
      - hostPath:
          path: /var/lib/rancher/k3s/data/current/bin
          type: Directory
        name: cnibin
      - hostPath:
          path: /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d
          type: DirectoryOrCreate
        name: multus-cfg
  updateStrategy:
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
    type: RollingUpdate
```

保存为 `multus-daemonset-k3s.yaml`，然后应用：

```bash
kubectl apply -f multus-daemonset-k3s.yaml
```

### 5.4 关键配置说明

#### 5.4.1 容器启动参数（最重要！）

```yaml
args:
  - --multus-conf-file=auto
  - --multus-autoconfig-dir=/host/etc/cni/net.d    # ✅ Pod 内路径
  - --cni-conf-dir=/host/etc/cni/net.d             # ✅ Pod 内路径
```

**为什么重要**：
- 如果使用 `/var/lib/rancher/k3s/agent/etc/cni/net.d`（主机路径），Multus 会在容器内拼接路径，导致重复
- 使用 `/host/etc/cni/net.d`（Pod 内路径），Multus 直接使用挂载后的路径，不会重复

#### 5.4.2 挂载配置

```yaml
volumes:
  - name: cni
    hostPath:
      path: /var/lib/rancher/k3s/agent/etc/cni/net.d  # 主机真实路径
      type: Directory
  - name: cnibin
    hostPath:
      path: /var/lib/rancher/k3s/data/current/bin     # 主机 CNI 二进制路径
      type: Directory

volumeMounts:
  - name: cni
    mountPath: /host/etc/cni/net.d                   # Pod 内访问路径
  - name: cnibin
    mountPath: /host/opt/cni/bin                      # Pod 内 CNI 二进制路径
```

**映射关系**：
- 主机 `/var/lib/rancher/k3s/agent/etc/cni/net.d` → Pod 内 `/host/etc/cni/net.d`
- 主机 `/var/lib/rancher/k3s/data/current/bin` → Pod 内 `/host/opt/cni/bin`

### 5.5 验证 Multus 安装

```bash
# 等待 Pod 启动（约 30 秒）
kubectl wait -n kube-system -l app=multus --for condition=Ready pod --timeout=120s

# 检查 Pod 状态
kubectl get pods -n kube-system -l app=multus

# 应该看到：
# NAME                READY   STATUS    RESTARTS   AGE
# kube-multus-ds-xxx  1/1     Running   0          1m

# 检查日志（应该没有路径错误）
POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n kube-system $POD -c kube-multus --tail=20

# 应该看到类似：
# kubeconfig is created in /host/etc/cni/net.d/multus.d/multus.kubeconfig
# kubeconfig file is created.
# master capabilities is get from conflist
# multus config file is created.
```

**成功标志**：
- ✅ Pod 状态为 `Running`
- ✅ 日志中没有 `cni-conf-dir is not found` 错误
- ✅ 日志显示 `kubeconfig is created` 和 `multus config file is created`

---

## 步骤 6: 验证所有组件

运行以下命令验证所有组件已正确安装：

```bash
echo "=== 1. 检查 k3s ==="
kubectl get nodes

echo -e "\n=== 2. 检查 KubeVirt ==="
kubectl get pods -n kubevirt
kubectl get kubevirt -n kubevirt

echo -e "\n=== 3. 检查 CDI ==="
kubectl get pods -n cdi
kubectl get cdi -n cdi

echo -e "\n=== 4. 检查 Multus ==="
kubectl get pods -n kube-system -l app=multus
kubectl get daemonset -n kube-system kube-multus-ds

echo -e "\n=== 5. 检查 CNI 配置 ==="
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

echo -e "\n=== 6. 检查 Multus 配置文件 ==="
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf 2>/dev/null || echo "配置文件尚未生成（可能需要等待）"
```

### 预期结果

所有组件应该都处于 `Running` 状态：

- ✅ k3s 节点：`Ready`
- ✅ KubeVirt：所有 Pods `Running`，CR 状态 `Deployed`
- ✅ CDI：所有 Pods `Running`，CR 状态 `Available`
- ✅ Multus：DaemonSet Pod `Running`，日志无错误

---

## 常见问题排查

### 问题 1: Multus Pod 一直 CrashLoopBackOff

**症状**：Pod 日志显示 `cni-conf-dir is not found: stat /host/var/lib/rancher/k3s/agent/var/lib/rancher/k3s/agent/etc/cni/net.d`

**原因**：容器启动参数使用了主机路径，导致路径重复

**解决**：
1. 检查 DaemonSet 的容器 args：
   ```bash
   kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A5 "args:"
   ```
2. 确保 args 中使用 `/host/etc/cni/net.d`（Pod 内路径），而不是 `/var/lib/rancher/k3s/agent/...`
3. 如果错误，使用正确的配置重新应用：
   ```bash
   kubectl apply -f tmp/kube-multus-ds-clean.yaml
   ```

### 问题 2: KubeVirt Pods 无法启动

**症状**：`virt-handler` 或 `virt-controller` 一直 `Pending` 或 `CrashLoopBackOff`

**可能原因**：
1. 节点没有 `kubevirt.io/schedulable=true` label
2. 硬件不支持虚拟化，但未启用软件模拟

**解决**：
```bash
# 1. 添加节点 label
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME kubevirt.io/schedulable=true --overwrite

# 2. 启用软件模拟（如果硬件不支持 KVM）
kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

### 问题 3: 无法从远程访问 k3s

**症状**：`kubectl get nodes` 报错 `connection refused`

**原因**：k3s.yaml 中的 server 地址是 `127.0.0.1`

**解决**：
```bash
# 查看当前 server 地址
grep server ~/.kube/config

# 修改为节点实际 IP
sed -i 's/127.0.0.1/你的节点IP/g' ~/.kube/config

# 或者使用环境变量
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### 问题 4: 镜像拉取失败

**症状**：Pod 状态为 `ImagePullBackOff`

**解决**：
```bash
# 检查镜像地址
kubectl describe pod -n <namespace> <pod-name> | grep Image

# 在节点上手动拉取（如果使用 containerd）
sudo crictl pull <镜像地址>

# 或者配置镜像加速器（根据你的环境）
```

---

## 安装检查清单

### ✅ 核心组件

- [ ] k3s 已安装并运行
- [ ] kubeconfig 已配置
- [ ] KubeVirt 已安装并运行
- [ ] CDI 已安装并运行
- [ ] Multus CNI 已安装并运行（无路径错误）

### ✅ 配置验证

- [ ] 节点有 `kubevirt.io/schedulable=true` label
- [ ] KubeVirt 已启用软件模拟（如需要）
- [ ] Multus DaemonSet 使用正确的启动参数
- [ ] Multus Pod 日志无错误

### ✅ 功能验证

- [ ] 可以创建 VirtualMachine
- [ ] 可以创建 VirtualMachineInstance
- [ ] Multus 可以创建 NetworkAttachmentDefinition
- [ ] 存储功能正常（CDI）

---

## 下一步

安装完成后，你可以：

1. **创建第一个虚拟机**：
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble.yaml
   ```

2. **检查 VM 状态**：
   ```bash
   kubectl get vm
   kubectl get vmi
   ```

3. **使用 virtctl 连接 VM**：
   ```bash
   # 安装 virtctl
   export VERSION=$(kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.observedKubeVirtVersion}')
   wget https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64
   chmod +x virtctl-${VERSION}-linux-amd64
   sudo mv virtctl-${VERSION}-linux-amd64 /usr/local/bin/virtctl

   # 连接 VM
   virtctl console <vm-name>
   ```

---

## 参考文档

- [k3s 官方文档](https://docs.k3s.io/)
- [KubeVirt 官方文档](https://kubevirt.io/)
- [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [k3s Multus 配置](https://docs.k3s.io/networking/multus-ipams)

---

**最后更新**: 2025-12-22  
**验证环境**: k3s v1.28.x, KubeVirt v1.2.0, Multus CNI snapshot

