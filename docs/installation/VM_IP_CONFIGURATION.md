# VM IP 配置说明

## 问题：如果 ens192 有固定 IP，VM 的 IP 是多少？

## 答案

**VM 的 IP 是 `ipConfig.address` 指定的值，与 ens192 的 IP 不同。**

### 配置示例

```yaml
networks:
  - name: external
    type: bridge
    physicalInterface: "ens192"
    nodeIP: "192.168.0.121/24"     # ens192 的原始 IP（节点 IP）
    ipConfig:
      mode: static
      address: "192.168.0.200/24"  # VM 的 IP（与 ens192 不同）
      gateway: "192.168.0.1"
```

### IP 分配说明

1. **节点 IP**：`nodeIP: "192.168.0.121/24"`
   - 这是 ens192 的原始固定 IP
   - 会迁移到桥接 `br-external` 上
   - 节点通过桥接访问网络

2. **VM IP**：`ipConfig.address: "192.168.0.200/24"`
   - 这是 VM 的 IP 地址
   - 通过 Cloud-Init 配置在 VM 内部
   - VM 通过桥接访问网络

### 代码实现

根据 `pkg/kubevirt/vm.go` 的代码（第 479-480 行）：

```go
cloudInit += "      addresses:\n"
cloudInit += fmt.Sprintf("        - %s\n", *net.IPConfig.Address)
```

VM 的 IP 是通过 `net.IPConfig.Address` 配置的，即 `ipConfig.address` 字段的值。

### 网络拓扑

```
节点：
  ens192 (原始 IP: 192.168.0.121/24)
    ↓
  br-external (节点 IP: 192.168.0.121/24) ← 节点通过这里访问网络
    ├── ens192 (作为桥接端口，无 IP)
    └── VM (VM IP: 192.168.0.200/24) ← VM 通过这里访问网络
```

### 重要说明

1. **两个不同的 IP**：
   - 节点 IP：`192.168.0.121/24`（在桥接上）
   - VM IP：`192.168.0.200/24`（在 VM 内部）

2. **必须在同一网段**：
   - 两者都在 `192.168.0.0/24` 网段
   - 可以互相通信

3. **都通过桥接访问外网**：
   - 节点通过桥接访问外网（IP: 192.168.0.121/24）
   - VM 通过桥接访问外网（IP: 192.168.0.200/24）

### 验证方法

在 VM 内检查 IP：

```bash
# 在 VM 内执行
ip addr show
# 应该看到：inet 192.168.0.200/24（ipConfig.address 指定的值）

# 检查网络连接
ping 8.8.8.8
ping 192.168.0.1
```

### 总结

**如果 ens192 有固定 IP `192.168.0.121/24`：**
- ✅ 节点 IP：`192.168.0.121/24`（迁移到桥接上）
- ✅ VM IP：`192.168.0.200/24`（`ipConfig.address` 指定的值）
- ✅ 两者是不同的 IP，在同一个网段
- ✅ 都通过桥接访问外网

