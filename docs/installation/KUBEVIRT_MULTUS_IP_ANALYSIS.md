# KubeVirt Multus IP 配置问题分析

## 官方文档调研结果

### 1. KubeVirt API 结构

根据 `kubevirt.io/api@v1.2.0` 的源码：

```go
type Network struct {
    Name string `json:"name"`
    NetworkSource `json:",inline"`
}

type NetworkSource struct {
    Pod    *PodNetwork    `json:"pod,omitempty"`
    Multus *MultusNetwork `json:"multus,omitempty"`
}
```

**结论：KubeVirt API v1.2.0 的 Network 结构体没有 `ipAddress` 字段。**

### 2. 静态 IP 配置方式

根据官方文档和实践，KubeVirt 中配置静态 IP 的正确方式是：

1. **通过 Cloud-Init 配置**（推荐）
   - 在 VM 的 Cloud-Init userdata 中配置网络
   - 使用 netplan 或 network-scripts 格式

2. **通过 NMState Operator**（高级）
   - 使用 NodeNetworkConfigurationPolicy
   - 需要额外的 Operator

### 3. 当前实现问题

我们的代码使用 Cloud-Init 配置网络，但可能存在以下问题：

1. **接口名称不匹配**
   - Cloud-Init 使用 `ubuntu-rulai-multus-external-nad` 作为接口名称
   - 但 VM 内部的接口名称可能不同

2. **接口名称生成规则**
   - KubeVirt 使用 Interface 的 `Name` 字段作为 VM 内部的接口名称
   - 我们的代码中，Interface 的 Name 是 `net.NADName`（`ubuntu-rulai-multus-external-nad`）
   - 但实际 VM 内部的接口名称可能遵循不同的规则

## 解决方案

### 方案 1：检查 VM 内部实际接口名称

```bash
# 通过 Pod IP 访问 VM
POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')
ssh ubuntu@$POD_IP
# 密码：ubuntu123

# 在 VM 内部检查接口
ip addr show
ip link show
```

### 方案 2：使用通配符匹配接口

修改 Cloud-Init 配置，使用通配符匹配接口：

```yaml
network:
  version: 2
  ethernets:
    enp*:  # 匹配所有 enp 开头的接口
      addresses:
        - 192.168.1.200/24
      gateway4: 192.168.1.1
```

### 方案 3：使用 MAC 地址匹配

如果知道接口的 MAC 地址，可以使用 MAC 地址匹配：

```yaml
network:
  version: 2
  ethernets:
    "match":
      macaddress: "a6:d6:cf:45:6d:d0"
    set-name: external
    addresses:
      - 192.168.1.200/24
    gateway4: 192.168.1.1
```

### 方案 4：检查 KubeVirt 接口命名规则

KubeVirt 可能使用以下规则命名接口：
- 第一个接口：`eth0` 或 `enp1s0`
- 第二个接口：`eth1` 或 `enp2s0`
- 或者使用接口的 MAC 地址生成名称

## 验证步骤

1. **检查 VM 内部接口**：
   ```bash
   ssh ubuntu@<POD_IP>
   ip addr show
   ```

2. **检查 Cloud-Init 日志**：
   ```bash
   kubectl logs <virt-launcher-pod> -c guest-console-log | grep -i network
   ```

3. **检查 Cloud-Init 配置**：
   ```bash
   kubectl get vm ubuntu-rulai-multus-vm -o yaml | grep -A 50 "userdata:"
   ```

## 参考

- [KubeVirt Network API](https://kubevirt.io/api-reference/main/definitions.html#_v1_network)
- [KubeVirt Networking Guide](https://kubevirt.io/user-guide/virtual_machines/networking/)
- [Cloud-Init Network Configuration](https://cloudinit.readthedocs.io/en/latest/topics/network-config.html)

