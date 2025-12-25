# k3s 官方安装指南（基于官方文档）

根据 [k3s 官方安装文档](https://docs.k3s.io/installation) 整理的关键要点。

## 单节点安装（Server 模式）

### 基本安装命令

```bash
curl -sfL https://get.k3s.io | sh -
```

### 关键配置选项

#### 1. 网络配置（Critical Configuration Values）

**必须明确指定**（特别是多节点，单节点也建议明确指定）：

```bash
--cluster-cidr <CIDR>      # Pod 网络，默认: 10.42.0.0/16
--service-cidr <CIDR>      # Service 网络，默认: 10.43.0.0/16
```

**重要**：
- 这些值必须在所有节点上相同
- 即使单节点，明确指定可以避免问题

#### 2. ServiceLB 配置

```bash
--disable servicelb        # 禁用内置 LoadBalancer
```

**何时禁用**：
- 不需要 LoadBalancer 功能
- 遇到 DNS 解析问题（如 198.18.x.x）
- 使用外部 LoadBalancer（如 MetalLB）

#### 3. 远程访问配置

```bash
--tls-san <IP或域名>       # 添加 TLS SAN，允许远程访问
```

**示例**：
```bash
--tls-san 192.168.1.141
--tls-san k3s.example.com
```

### 完整安装命令示例

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --tls-san 192.168.1.141 \
  --cluster-cidr 10.42.0.0/16 \
  --service-cidr 10.43.0.0/16 \
  --disable servicelb" sh -
```

## 安装后验证

### 1. 检查服务状态

```bash
sudo systemctl status k3s
```

### 2. 检查节点

```bash
sudo k3s kubectl get nodes
```

### 3. 配置 kubeconfig

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### 4. 验证配置

```bash
# 检查实际启动参数
sudo systemctl cat k3s | grep -A 10 "ExecStart"

# 检查版本
k3s --version
```

## 常见问题

### DNS 解析问题（解析到 198.18.x.x）

**根本原因**：系统中存在名为 "Meta" 的网络设备，该设备有 198.18.x.x 的 IP 地址，导致 DNS 解析错误。

**解决方案**：

1. **检查 Meta 设备**
   ```bash
   ip link show | grep Meta
   ip addr show Meta
   ```

2. **删除 Meta 设备**
   ```bash
   sudo ip link set Meta down
   sudo ip link delete Meta
   ```

3. **重启系统**
   ```bash
   sudo reboot
   ```

4. **验证 DNS 解析**
   ```bash
   kubectl run -it --rm test-dns --image=busybox --restart=Never -- \
     nslookup kubernetes.default.svc.cluster.local
   ```

**注意**：删除 Meta 设备后需要重启系统，确保配置生效。

**其他检查项**（如果删除 Meta 设备后问题仍然存在）：

1. **检查 ServiceLB 是否禁用**
   ```bash
   sudo systemctl cat k3s | grep "disable.*servicelb"
   ```

2. **检查网络配置**
   ```bash
   sudo systemctl cat k3s | grep -E "cluster-cidr|service-cidr"
   ```

### 卸载 k3s

```bash
/usr/local/bin/k3s-uninstall.sh
```

## 注意事项

1. **系统要求**：
   - Linux 内核 3.10+
   - 至少 512MB RAM
   - 至少 1 CPU 核心

2. **防火墙**：
   - 确保 6443 端口开放（API server）
   - 如果远程访问，确保防火墙规则正确

3. **配置文件位置**：
   - k3s 配置：`/etc/rancher/k3s/k3s.yaml`
   - systemd 服务：`/etc/systemd/system/k3s.service`

4. **数据目录**：
   - 默认：`/var/lib/rancher/k3s`
   - 包含所有集群数据

## 当前安装脚本检查清单

### ✅ 已实现的配置

1. **网络配置**：
   - ✅ `--cluster-cidr 10.42.0.0/16`（明确指定）
   - ✅ `--service-cidr 10.43.0.0/16`（明确指定）

2. **ServiceLB 控制**：
   - ✅ 支持通过 `DISABLE_SERVICELB=true` 禁用

3. **远程访问**：
   - ✅ `--tls-san ${SERVER_IP}`（默认 192.168.1.141）

4. **版本控制**：
   - ✅ 支持指定版本或使用最新版本

5. **安装后验证**：
   - ✅ 检查服务状态
   - ✅ 配置 kubeconfig
   - ✅ 验证节点状态

### 📝 安装脚本使用方法

```bash
# 方式 1：使用最新版本 + 禁用 ServiceLB（推荐，解决 DNS 问题）
DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh

# 方式 2：使用指定版本
K3S_VERSION="v1.29.6+k3s1" DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh

# 方式 3：使用最新版本 + 启用 ServiceLB
./docs/installation/install-k3s-only.sh
```

## 参考文档

- [k3s 安装文档](https://docs.k3s.io/installation)
- [k3s 配置选项](https://docs.k3s.io/cli/server)
- [k3s 网络配置](https://docs.k3s.io/networking)

