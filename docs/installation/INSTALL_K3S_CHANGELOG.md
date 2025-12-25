# install-k3s-only.sh 变更记录

## 主要变化对比

### 之前的版本（初始版本）

```bash
# 简单的安装命令
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_EXEC="server --tls-san ${SERVER_IP}" sh -
```

**特点**：
- ✅ 固定 k3s 版本：`v1.29.6+k3s1`
- ✅ 支持远程访问：`--tls-san ${SERVER_IP}`
- ❌ 无法控制 ServiceLB
- ❌ 没有 DNS 问题提示

### 当前版本（最新）

```bash
# 动态构建启动参数
K3S_SERVER_ARGS="server --tls-san ${SERVER_IP}"

# 如果禁用 ServiceLB
if [[ "${DISABLE_SERVICELB}" =~ ^[Tt]rue$ ]]; then
    K3S_SERVER_ARGS="${K3S_SERVER_ARGS} --disable servicelb"
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_EXEC="${K3S_SERVER_ARGS}" sh -
```

**特点**：
- ✅ 固定 k3s 版本：`v1.29.6+k3s1`（保持不变）
- ✅ 支持远程访问：`--tls-san ${SERVER_IP}`（保持不变）
- ✅ **新增**：支持通过环境变量 `DISABLE_SERVICELB=true` 禁用 ServiceLB
- ✅ **新增**：DNS 问题诊断提示
- ✅ **新增**：更详细的安装后说明

## 详细变更列表

### 1. 新增 ServiceLB 控制功能

**位置**：第 44-58 行

**新增内容**：
```bash
# 是否禁用 ServiceLB（如果遇到 DNS 解析到 198.18.x.x 的问题，可以禁用）
# 禁用 ServiceLB 后，将无法使用 LoadBalancer 类型的 Service
# 可以通过环境变量 DISABLE_SERVICELB=true 来禁用
DISABLE_SERVICELB="${DISABLE_SERVICELB:-false}"

# 构建 k3s server 启动参数
K3S_SERVER_ARGS="server --tls-san ${SERVER_IP}"

# 如果禁用 ServiceLB
if [[ "${DISABLE_SERVICELB}" =~ ^[Tt]rue$ ]]; then
    echo_warn "  ⚠️  将禁用 ServiceLB（无法使用 LoadBalancer 类型的 Service）"
    K3S_SERVER_ARGS="${K3S_SERVER_ARGS} --disable servicelb"
else
    echo_info "  ServiceLB 已启用（可以使用 LoadBalancer 类型的 Service）"
fi
```

**用途**：
- 解决 DNS 解析到 `198.18.x.x` 的问题
- 如果不需要 LoadBalancer 功能，可以禁用 ServiceLB

### 2. 修改安装命令

**之前**：
```bash
INSTALL_K3S_EXEC="server --tls-san ${SERVER_IP}"
```

**现在**：
```bash
INSTALL_K3S_EXEC="${K3S_SERVER_ARGS}"
```

**原因**：支持动态添加参数（如 `--disable servicelb`）

### 3. 新增 DNS 验证提示

**位置**：第 117-121 行

**新增内容**：
```bash
# 提示 DNS 验证
echo_info "7. DNS 验证提示..."
echo_info "  如果遇到 DNS 解析到 198.18.x.x 的问题，可以运行："
echo_info "    kubectl run -it --rm test-dns --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local"
echo_info "  如果解析到 198.18.x.x 且无法连接，可以禁用 ServiceLB 重新安装"
```

**用途**：帮助用户诊断和解决 DNS 问题

### 4. 增强安装后说明

**位置**：第 129-131 行

**新增内容**：
```bash
echo_info "如果遇到 DNS 解析到 198.18.x.x 的问题："
echo_info "  参考文档: docs/installation/DNS_198_18_ISSUE.md"
echo_info "  解决方案: DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
```

**用途**：提供问题解决方案的快速参考

## 使用方式对比

### 之前的使用方式

```bash
# 直接运行（固定配置）
./docs/installation/install-k3s-only.sh
```

### 现在的使用方式

```bash
# 方式 1：默认安装（启用 ServiceLB）
./docs/installation/install-k3s-only.sh

# 方式 2：禁用 ServiceLB（解决 DNS 问题）
DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh
```

## 变更原因

1. **解决 DNS 问题**：
   - 发现 DNS 解析到 `198.18.x.x` 导致连接失败
   - 禁用 ServiceLB 可以解决此问题

2. **提高灵活性**：
   - 支持根据需求选择是否启用 ServiceLB
   - 保持向后兼容（默认行为不变）

3. **改善用户体验**：
   - 添加问题诊断提示
   - 提供解决方案参考

## 向后兼容性

✅ **完全向后兼容**

- 默认行为不变：如果不设置 `DISABLE_SERVICELB`，行为与之前完全一致
- 现有脚本和文档无需修改
- 新功能通过环境变量控制，不影响现有使用方式

## 相关文档

- [DNS 198.18 问题诊断](./DNS_198_18_ISSUE.md)
- [k3s 配置分析](./K3S_CONFIG_ANALYSIS.md)
- [k3s 卸载脚本](./uninstall-k3s.sh)

