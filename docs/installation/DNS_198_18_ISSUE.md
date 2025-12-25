# DNS 解析到 198.18.x.x 问题诊断和解决方案

## 问题确认

### 测试结果

1. **DNS 解析结果**：
   ```bash
   kubectl run -it --rm test-dns --image=busybox --restart=Never -- \
     nslookup kubernetes.default.svc.cluster.local
   # 结果：198.18.0.47（错误）
   ```

2. **连接测试**：
   ```bash
   # 测试 198.18.0.47（DNS 解析到的地址）
   wget https://198.18.0.47:443
   # 结果：Connection reset by peer（失败）
   
   # 测试 10.43.0.1（实际的 ClusterIP）
   wget https://10.43.0.1:443
   # 结果：HTTP/1.1 401 Unauthorized（成功，只是需要认证）
   ```

### 结论

- ✅ **实际 ClusterIP 正确**：`10.43.0.1` 可以正常连接
- ❌ **DNS 解析错误**：解析到 `198.18.0.47`，无法连接
- 🔍 **影响**：导致 Longhorn webhook 健康检查失败（无法连接到自己的 Service）

## 可能的原因

### 1. ServiceLB 行为（最可能）

k3s 的 ServiceLB 使用 `198.18.0.0/15` 作为虚拟 IP 范围。虽然 `kubernetes` Service 是 ClusterIP 类型，不应该被 ServiceLB 处理，但可能存在以下情况：

- ServiceLB 的某些实现可能影响了 DNS 解析
- k3s 版本的 bug 或特殊行为

### 2. CoreDNS 配置问题

- CoreDNS 可能有 hosts 插件配置
- 可能有自定义配置文件导致解析错误

### 3. k3s 版本问题

- k3s v1.29.6+k3s1 可能存在已知的 DNS 解析问题
- 需要检查是否有相关 issue

## 诊断步骤

运行以下命令进行诊断：

```bash
# 1. 检查 ServiceLB Pods
kubectl get pods -n kube-system -l app=svclb

# 2. 检查 CoreDNS 配置
kubectl get configmap coredns -n kube-system -o yaml | grep -A 50 "Corefile:"

# 3. 检查 CoreDNS 自定义配置
COREDNS_POD=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
kubectl exec -n kube-system ${COREDNS_POD} -- ls -la /etc/coredns/custom/ 2>&1

# 4. 检查网络路由
ip route | grep -E "198.18|10.42|10.43"

# 5. 检查 k3s 版本
k3s --version

# 6. 检查是否有 LoadBalancer 类型的 Service
kubectl get svc -A | grep LoadBalancer
```

## 解决方案

### 方案 1：禁用 ServiceLB（推荐，如果不需要 LoadBalancer）

如果项目不需要 LoadBalancer 类型的 Service，可以禁用 ServiceLB：

**优点**：
- 可能解决 DNS 解析问题
- 减少资源占用
- 避免 ServiceLB 的潜在问题

**缺点**：
- 无法使用 LoadBalancer 类型的 Service
- 需要重新安装 k3s

**实施步骤**：

1. 修改安装脚本 `docs/installation/install-k3s-only.sh`：
   ```bash
   INSTALL_K3S_EXEC="server --tls-san ${SERVER_IP} --disable servicelb"
   ```

2. 重新安装 k3s（会清理现有集群）：
   ```bash
   # 卸载现有 k3s
   /usr/local/bin/k3s-uninstall.sh
   
   # 重新安装
   ./docs/installation/install-k3s-only.sh
   ```

### 方案 2：修复 CoreDNS 配置（如果确认是 CoreDNS 问题）

如果诊断确认是 CoreDNS 配置问题，可以：

1. 检查并修复 CoreDNS ConfigMap
2. 删除有问题的 hosts 插件配置
3. 重启 CoreDNS Pods

### 方案 3：升级/降级 k3s（如果是版本问题）

如果确认是 k3s 版本的 bug：

1. 检查 k3s GitHub issues
2. 升级到修复版本，或降级到稳定版本

### 方案 4：使用 IP 地址而不是 DNS（临时方案）

如果无法立即修复，可以临时修改 Longhorn 配置，使用 IP 地址而不是 DNS 名称。但这不推荐，因为：

- 配置不灵活
- 维护困难
- 不是根本解决方案

## 推荐方案

**基于当前情况，推荐使用方案 1（禁用 ServiceLB）**，原因：

1. ✅ 测试确认 DNS 解析错误
2. ✅ 如果不需要 LoadBalancer，禁用 ServiceLB 是安全的
3. ✅ 可能解决根本问题
4. ✅ 符合 k3s 官方文档的建议（单节点集群通常不需要 ServiceLB）

## 实施建议

### 如果选择方案 1（禁用 ServiceLB）

1. **确认项目需求**：
   - 是否需要 LoadBalancer 类型的 Service？
   - 如果不需要，可以安全禁用

2. **修改安装脚本**：
   - 更新 `docs/installation/install-k3s-only.sh`
   - 添加 `--disable servicelb` 参数

3. **重新安装**：
   - 备份重要数据
   - 卸载现有 k3s
   - 使用新脚本重新安装

4. **验证**：
   - 检查 DNS 解析是否正常
   - 验证 Longhorn 是否能正常工作

## 注意事项

1. **重新安装会清理集群**：
   - 所有 Pod、Service、ConfigMap 等都会被删除
   - 需要重新安装 Longhorn、KubeVirt 等组件

2. **数据备份**：
   - 如果有重要数据，需要先备份
   - Longhorn 的数据需要单独备份

3. **测试环境优先**：
   - 建议先在测试环境验证
   - 确认问题解决后再应用到生产环境

## 相关文档

- [k3s Server CLI 文档](https://docs.k3s.io/cli/server)
- [k3s ServiceLB 文档](https://docs.k3s.io/networking/service-lb)
- [k3s 网络配置](https://docs.k3s.io/networking)

