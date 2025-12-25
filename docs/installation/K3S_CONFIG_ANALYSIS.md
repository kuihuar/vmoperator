# k3s 安装配置分析

根据 [k3s 官方文档](https://docs.k3s.io/cli/server) 分析当前安装脚本的配置。

## 当前安装脚本配置

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_EXEC="server --tls-san ${SERVER_IP}" sh -
```

**使用的参数**：
- `--tls-san ${SERVER_IP}`：用于远程访问，正确 ✅

**未指定的参数（使用默认值）**：
- `--cluster-cidr`：默认 `10.42.0.0/16`（Pod 网络）
- `--service-cidr`：默认 `10.43.0.0/16`（Service 网络）
- `--disable servicelb`：未指定，ServiceLB 默认启用

## 官方文档要求分析

### 关键配置值（Critical Configuration Values）

根据官方文档，以下配置**必须在集群所有节点上设置为相同的值**：

- ✅ `--cluster-cidr`：当前使用默认值 `10.42.0.0/16`
- ✅ `--service-cidr`：当前使用默认值 `10.43.0.0/16`
- ⚠️ `--disable=servicelb`：当前未指定，ServiceLB 默认启用

**分析**：
- **单节点集群**：使用默认值是可以的，不会有问题
- **多节点集群**：如果将来要扩展，必须明确指定这些值，确保所有节点一致
- **当前项目**：如果只是单节点，当前配置是**正确的**

### 关于 198.18.x.x 地址问题

**可能的原因**（需要诊断确认）：

1. **ServiceLB 行为**：
   - k3s ServiceLB 可能在某些情况下使用 198.18.0.0/15 作为虚拟 IP
   - 但这不应该影响 `kubernetes.default.svc` 的 DNS 解析
   - `kubernetes` Service 是 ClusterIP 类型，应该解析到 `10.43.0.1`

2. **CoreDNS 配置问题**：
   - CoreDNS 可能有 hosts 插件或其他配置导致解析错误
   - 需要检查 CoreDNS ConfigMap

3. **网络配置问题**：
   - 节点网络配置或路由问题
   - 需要检查实际网络状态

## 配置建议

### 方案 A：保持当前配置（单节点，推荐）

**适用场景**：单节点集群，不需要 LoadBalancer

**配置**：
```bash
# 当前配置即可，使用默认值
INSTALL_K3S_EXEC="server --tls-san ${SERVER_IP}"
```

**优点**：
- 简单，符合 k3s 官方推荐
- 默认配置已经过充分测试

**注意事项**：
- 如果将来要扩展为多节点，需要重新安装并明确指定所有关键配置值

### 方案 B：明确指定关键配置（多节点准备，或解决 198.18 问题）

**适用场景**：
- 计划扩展为多节点集群
- 需要禁用 ServiceLB（如果不需要 LoadBalancer）
- 解决 198.18.x.x 地址问题

**配置**：
```bash
INSTALL_K3S_EXEC="server \
  --tls-san ${SERVER_IP} \
  --cluster-cidr 10.42.0.0/16 \
  --service-cidr 10.43.0.0/16 \
  --disable servicelb"
```

**优点**：
- 明确配置，便于将来扩展
- 禁用 ServiceLB 可能解决 198.18.x.x 问题

**缺点**：
- 如果将来需要 LoadBalancer，需要重新启用 ServiceLB

## 诊断步骤（必须先执行）

在决定是否修改配置之前，先运行以下诊断：

```bash
# 1. 检查 k3s 实际运行的参数
sudo ps aux | grep "k3s" | grep -v grep

# 2. 检查 ServiceLB
kubectl get pods -n kube-system -l app=svclb

# 3. 检查 CoreDNS 配置
kubectl get configmap coredns -n kube-system -o yaml | grep -A 50 "Corefile:"

# 4. 检查是否有 LoadBalancer 类型的 Service
kubectl get svc -A | grep LoadBalancer

# 5. 检查网络路由
ip route | grep -E "198.18|10.42|10.43"
```

## 结论

### 当前安装方法是否正确？

**✅ 是的，当前安装方法是正确的**

- 使用官方安装脚本：正确
- 指定版本：正确
- 添加 `--tls-san`：正确
- 使用默认网络配置：对于单节点是正确的

### 是否需要修改？

**取决于**：

1. **如果只是单节点**：
   - ✅ 当前配置可以，不需要修改
   - 但建议明确指定关键配置值，便于将来扩展

2. **如果要解决 198.18.x.x 问题**：
   - 先运行诊断命令，确定问题原因
   - 如果确认是 ServiceLB 导致的，可以添加 `--disable servicelb`
   - 但需要确认项目是否需要 LoadBalancer 功能

3. **如果要扩展为多节点**：
   - ⚠️ 必须明确指定所有关键配置值
   - 确保所有节点使用相同的 `--cluster-cidr`、`--service-cidr` 等

## 建议的修改（可选）

如果确定要明确配置，可以这样修改：

```bash
# 明确指定关键配置值（便于将来扩展，或解决 198.18 问题）
INSTALL_K3S_EXEC="server \
  --tls-san ${SERVER_IP} \
  --cluster-cidr 10.42.0.0/16 \
  --service-cidr 10.43.0.0/16 \
  --disable servicelb"
```

**但建议**：
1. 先运行诊断命令，确认 198.18.x.x 的真正原因
2. 确认项目是否需要 LoadBalancer 功能
3. 再决定是否添加 `--disable servicelb`

## 相关文档

- [k3s Server CLI 文档](https://docs.k3s.io/cli/server)
- [k3s 网络配置](https://docs.k3s.io/networking)
- [k3s 关键配置值说明](https://docs.k3s.io/cli/server#critical-configuration-values)

