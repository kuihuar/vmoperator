# 技术栈 Helm 包管理总览

## 1. 概述

项目依赖多个技术栈，需要统一通过 Helm 进行管理，确保：
- 版本一致性
- 依赖关系清晰
- 部署流程标准化
- 环境配置统一

## 2. 技术栈列表

项目涉及的核心技术栈：

1. **k3s** - 轻量级 Kubernetes 发行版
2. **KubeVirt** - 虚拟机管理 Operator
3. **CDI** - 容器化数据导入工具
4. **Multus CNI** - 多网络接口支持
5. **NMState Operator** - 节点网络配置管理
6. **Longhorn** - 分布式块存储系统
7. **cert-manager** - 证书管理（可选，用于 Webhook）

## 3. 文档结构

1. **[15.1-k3s Helm管理规划.md](./15.1-k3s Helm管理规划.md)** - k3s 安装和配置管理
2. **[15.2-KubeVirt Helm管理规划.md](./15.2-KubeVirt Helm管理规划.md)** - KubeVirt 部署和配置
3. **[15.3-CDI Helm管理规划.md](./15.3-CDI Helm管理规划.md)** - CDI 部署和配置
4. **[15.4-Multus Helm管理规划.md](./15.4-Multus Helm管理规划.md)** - Multus CNI 部署和配置
5. **[15.5-NMState Helm管理规划.md](./15.5-NMState Helm管理规划.md)** - NMState Operator 部署和配置
6. **[15.6-Longhorn Helm管理规划.md](./15.6-Longhorn Helm管理规划.md)** - Longhorn 存储部署和配置
7. **[15.7-cert-manager Helm管理规划.md](./15.7-cert-manager Helm管理规划.md)** - cert-manager 部署和配置
8. **[15.8-依赖关系与部署顺序.md](./15.8-依赖关系与部署顺序.md)** - 技术栈依赖关系和部署顺序
9. **[15.9-统一部署方案.md](./15.9-统一部署方案.md)** - 使用 Helm 统一管理所有依赖

## 4. 部署策略

### 4.1 独立部署
每个技术栈可以独立部署，适合：
- 开发环境
- 逐步迁移
- 灵活配置

### 4.2 统一部署
通过主 Chart 管理所有依赖，适合：
- 生产环境
- 快速部署
- 版本一致性

## 5. 版本兼容性矩阵

| 技术栈 | 推荐版本 | 最低版本 | 备注 |
|--------|---------|---------|------|
| k3s | latest | 1.24+ | 轻量级 K8s |
| KubeVirt | 1.0+ | 0.58+ | 虚拟机管理 |
| CDI | 1.57+ | 1.50+ | 数据导入 |
| Multus | 4.0+ | 3.9+ | 多网络 |
| NMState | 0.73+ | 0.70+ | 网络配置 |
| Longhorn | 1.8.1+ | 1.6+ | 分布式存储 |
| cert-manager | 1.13+ | 1.10+ | 证书管理 |

## 6. 快速开始

### 6.1 独立部署
```bash
# 部署 KubeVirt
helm install kubevirt kubevirt/kubevirt --version 1.0.0

# 部署 CDI
helm install cdi kubevirt/cdi --version 1.57.0

# 部署 Multus
helm install multus k8snetworkplumbingwg/multus-cni

# 部署 NMState
helm install nmstate nmstate/nmstate-operator

# 部署 Longhorn
helm install longhorn longhorn/longhorn --version 1.8.1
```

### 6.2 统一部署（规划中）
```bash
# 使用主 Chart 部署所有依赖
helm install novasphere-stack ./charts/novasphere-stack \
  --namespace novasphere-system \
  --create-namespace
```

