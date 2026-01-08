# Multus CNI 在 K3s 上的修复总结

## 问题描述

VM 在使用 Multus CNI 配置外部网络时，一直卡在 `Starting` 状态，无法正常运行。经过多次调试和修复，最终成功解决了问题。

## 最终状态

- ✅ VM 状态：`Running`
- ✅ Multus 网络接口已创建：`fa96c2c1834-nic`
- ✅ Pod 网络正常：`eth0: 10.42.0.168`
- ✅ NAD 配置正确

## 修复步骤总结

### 修复 1：注册 apiextensions scheme

**问题：** `context canceled` 错误，提示 `no kind is registered for the type v1.CustomResourceDefinition`

**修复：** 在 `cmd/main.go` 中添加 `apiextensionsv1.AddToScheme(scheme)`

```go
import (
    apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
)

func init() {
    // ...
    _ = apiextensionsv1.AddToScheme(scheme)
}
```

### 修复 2：修正 Multus CRD 名称

**问题：** Controller 无法找到 Multus CRD

**修复：** 在 `pkg/network/multus.go` 中修正 CRD 名称

```go
// 错误：networkattachmentdefinitions.k8s.cni.cncf.io
// 正确：network-attachment-definitions.k8s.cni.cncf.io
```

### 修复 3：跳过 default 网络创建 NAD

**问题：** "default" 网络不应该通过 Multus 创建 NAD，应该使用 Pod 网络

**修复：** 在 `pkg/network/multus.go` 的 `ReconcileNetworks` 函数中添加跳过逻辑

```go
for _, netCfg := range vmp.Spec.Networks {
    // 跳过 default 网络，它使用 Pod 网络，不需要 Multus NAD
    if netCfg.Name == "default" {
        statuses = append(statuses, vmv1alpha1.NetworkStatus{
            Name: netCfg.Name,
            // 不设置 NADName，表示使用默认 Pod 网络
        })
        continue
    }
    // ...
}
```

### 修复 4：移除手动 Multus 注解

**问题：** 手动添加的 `k8s.v1.cni.cncf.io/networks` 注解与 KubeVirt 的自动处理冲突

**修复：** 在 `pkg/kubevirt/vm.go` 中移除手动创建 Multus 注解的代码，让 KubeVirt 根据 VM 的 network spec 自动处理

### 修复 5：修复 CNI IPAM 配置

**问题：** macvlan 静态 IP 的 IPAM 配置中，`subnet` 字段使用了 IP 地址而不是网络地址

**修复：** 在 `pkg/network/multus.go` 中正确解析 CIDR

```go
if netCfg.Type == "macvlan" {
    address := *netCfg.IPConfig.Address
    ip, ipNet, err := net.ParseCIDR(address)
    if err != nil {
        return "", fmt.Errorf("invalid IP address format: %s", address)
    }
    subnet := ipNet.String()  // 子网：192.168.1.0/24
    ipStr := ip.String()       // IP：192.168.1.200
    
    cfg.IPAM = map[string]interface{}{
        "type": "host-local",
        "ranges": [][]map[string]interface{}{
            {
                map[string]interface{}{
                    "subnet":     subnet,    // 子网地址
                    "rangeStart": ipStr,     // 起始 IP
                    "rangeEnd":   ipStr,     // 结束 IP（单个 IP）
                },
            },
        },
    }
}
```

### 修复 6：添加 macvlan CNI 插件

**问题：** `/opt/cni/bin` 目录中缺少 `macvlan` 插件

**修复：** 从 CNI 插件包中复制 `macvlan` 到 `/opt/cni/bin`

```bash
# 下载 CNI 插件
wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
tar -xzf cni-plugins-linux-amd64-v1.3.0.tgz
sudo cp macvlan /opt/cni/bin/
```

### 修复 7：复制 Multus 配置文件到 k3s 目录

**问题：** Multus 配置文件在 `/etc/cni/net.d/`，但 k3s 使用 `/var/lib/rancher/k3s/agent/etc/cni/net.d/`

**修复：** 复制配置文件到 k3s 目录

```bash
sudo cp /etc/cni/net.d/00-multus.conflist /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conflist
```

### 修复 8：创建 multus 符号链接（关键修复）

**问题：** k3s 在 `/var/lib/rancher/k3s/data/cni` 查找 CNI 插件，但 multus 在 `/opt/cni/bin`

**错误信息：**
```
Failed to create pod sandbox: failed to find plugin "multus" in path [/var/lib/rancher/k3s/data/cni]
```

**修复：** 创建符号链接

```bash
sudo ln -s /opt/cni/bin/multus /var/lib/rancher/k3s/data/cni/multus
```

**验证：**
```bash
ls -la /var/lib/rancher/k3s/data/cni/multus
# 输出：lrwxrwxrwx 1 root root 19 Jan  7 21:32 /var/lib/rancher/k3s/data/cni/multus -> /opt/cni/bin/multus
```

## 根本原因

**核心问题：** k3s 使用非标准的 CNI 路径结构

- **标准路径：** `/opt/cni/bin`（CNI 插件）、`/etc/cni/net.d`（CNI 配置）
- **k3s 路径：** `/var/lib/rancher/k3s/data/cni`（CNI 插件）、`/var/lib/rancher/k3s/agent/etc/cni/net.d`（CNI 配置）

Multus 安装时使用标准路径，但 k3s 在非标准路径查找插件和配置，导致无法找到 multus 插件。

## 验证步骤

### 1. 检查 multus 符号链接
```bash
ls -la /var/lib/rancher/k3s/data/cni/multus
```

### 2. 检查 Multus 配置文件
```bash
ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conflist
```

### 3. 检查 VM 状态
```bash
kubectl get vm ubuntu-rulai-multus-vm
kubectl get vmi ubuntu-rulai-multus-vm
```

### 4. 检查网络接口
```bash
kubectl get pod -l kubevirt.io=virt-launcher | grep ubuntu-rulai-multus | \
  awk '{print $1}' | xargs -I {} kubectl exec {} -c compute -- ip addr show
```

应该能看到：
- `eth0`: Pod 网络接口
- `fa96c2c1834-nic`: Multus 创建的网络接口

### 5. 检查 NAD
```bash
kubectl get net-attach-def ubuntu-rulai-multus-external-nad -o yaml
```

## 预防措施

为了避免将来再次出现类似问题，建议：

1. **在安装 Multus 时，直接配置 k3s 路径**
   - 修改 Multus DaemonSet 的 `hostPath` 挂载点
   - 或创建符号链接作为安装脚本的一部分

2. **文档化 k3s 的特殊路径要求**
   - 在安装文档中明确说明 k3s 的 CNI 路径差异
   - 提供自动化脚本处理路径映射

3. **创建安装后验证脚本**
   - 检查 multus 插件是否在正确路径
   - 检查 Multus 配置文件是否在正确路径
   - 验证 CNI 插件是否完整

## 相关文件

- `pkg/network/multus.go`: Multus 网络协调逻辑
- `pkg/kubevirt/vm.go`: VM 对象构建逻辑
- `cmd/main.go`: Controller 主程序入口
- `docs/installation/multus-daemonset-v4.0.2.yml`: Multus DaemonSet 配置
- `config/samples/vm_v1alpha1_wukong_rulai_multus.yaml`: VM 配置示例

## 参考

- [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [K3s CNI 配置](https://docs.k3s.io/networking)
- [KubeVirt 网络配置](https://kubevirt.io/user-guide/virtual_machines/networking/)

