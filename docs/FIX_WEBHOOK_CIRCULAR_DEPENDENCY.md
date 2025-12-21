# 修复 Longhorn Manager Webhook 循环依赖问题

## 问题描述

**错误信息**:
```
Error starting webhooks: admission webhook service is not accessible on cluster after 2m0s sec: timed out waiting for endpoint https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/healthz to be available
```

**问题根源**:
- Manager Pod 启动时需要检查 webhook 服务是否可用
- 但 webhook 服务就是由 Manager Pod 自己提供的（集成在 Manager 中）
- 形成了循环依赖：Manager 需要 webhook，但 webhook 需要 Manager 运行

## 问题分析

在 Longhorn v1.10.1 中：
- ✅ admission-webhook 功能集成在 `longhorn-manager` Pod 中
- ✅ Manager Pod 监听 9502 端口提供 webhook 服务
- ✅ Service 选择器匹配 Manager Pod
- ❌ Manager 启动时会检查 webhook 服务，导致循环依赖

## 解决方案

### 方案 1: 修复其他启动问题，让 Manager 能成功启动（推荐）

如果 Manager 还有其他启动问题（DNS、open-iscsi 等），先修复这些问题：

```bash
# 1. 检查 DNS 问题
kubectl logs -n longhorn-system -l app=longhorn-manager 2>&1 | grep -i "dns\|resolve"
# 如果有 DNS 错误，修复 k3s DNS
sudo ./scripts/fix-k3s-dns-for-longhorn.sh

# 2. 检查 open-iscsi 问题
kubectl logs -n longhorn-system -l app=longhorn-manager 2>&1 | grep -i "iscsi"
# 如果有，安装 open-iscsi
sudo apt-get install -y open-iscsi
sudo systemctl enable iscsid && sudo systemctl start iscsid

# 3. 修复后重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 方案 2: 检查是否有配置可以增加超时时间

```bash
# 检查 Manager DaemonSet 的环境变量
kubectl get daemonset -n longhorn-system longhorn-manager -o yaml | grep -A 30 "env:"

# 检查 Longhorn Settings
kubectl get settings -n longhorn-system
```

### 方案 3: 降级到已知稳定版本（如果问题持续）

如果 v1.10.1 存在这个启动顺序问题，可以降级到之前稳定的版本：

```bash
# 卸载当前版本
helm uninstall longhorn -n longhorn-system
kubectl delete namespace longhorn-system
sleep 60

# 安装稳定版本（例如 v1.6.0 或 v1.8.0）
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.8.0 \
  --values config/longhorn-values.yaml
```

### 方案 4: 查看 Longhorn GitHub Issues

这可能是 v1.10.1 的一个已知 bug，查看是否有解决方案或补丁：

```bash
# 搜索相关 Issues
# https://github.com/longhorn/longhorn/issues?q=webhook+timeout+v1.10
# https://github.com/longhorn/longhorn/issues?q=admission+webhook+circular
```

## 临时绕过方案（实验性）

### 临时禁用 webhook 检查（如果 Manager 支持）

检查 Manager 是否支持跳过 webhook 检查的启动参数：

```bash
# 检查 Manager 启动命令和参数
kubectl get daemonset -n longhorn-system longhorn-manager -o yaml | grep -A 10 "command:\|args:"
```

如果支持，可以添加启动参数来跳过 webhook 检查。

## 诊断步骤

```bash
# 1. 运行诊断脚本
./scripts/diagnose-manager-crash-root-cause.sh

# 2. 检查是否有其他错误
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100 | grep -i "error\|fatal" | grep -v "webhook"

# 3. 检查所有问题
./scripts/fix-webhook-circular-dependency.sh
```

## 推荐的完整修复流程

1. **先修复其他启动问题**（DNS、open-iscsi 等）
2. **确保所有前置条件满足**
3. **如果只是 webhook 循环依赖**：
   - 检查是否有配置可以增加超时
   - 查看 GitHub Issues 是否有解决方案
   - 考虑降级到稳定版本
4. **如果以上都不行**：等待 Longhorn 发布修复版本

## 相关链接

- Longhorn GitHub Issues: https://github.com/longhorn/longhorn/issues
- Longhorn 发布说明: https://github.com/longhorn/longhorn/releases
- Longhorn 文档: https://longhorn.io/docs/

