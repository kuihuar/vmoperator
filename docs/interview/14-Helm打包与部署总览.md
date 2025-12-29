# Helm 打包与部署总览

## 1. 概述

### 1.1 当前部署方式
- **开发测试**: 使用 `make deploy`，基于 Kustomize
- **生产环境**: 需要 Helm Chart 支持

### 1.2 目标
- 保持 `make deploy` 用于开发测试
- 提供 Helm Chart 用于生产部署
- 支持多环境配置（开发、测试、生产）
- 支持参数化配置

## 2. 文档结构

1. **[14.1-当前部署方式详解.md](./14.1-当前部署方式详解.md)** - 当前 Kustomize 部署方式说明
2. **[14.2-Helm Chart 结构设计.md](./14.2-Helm Chart 结构设计.md)** - Helm Chart 目录结构和模板设计
3. **[14.3-Values 配置说明.md](./14.3-Values 配置说明.md)** - Helm Values 参数详解
4. **[14.4-多环境部署策略.md](./14.4-多环境部署策略.md)** - 开发、测试、生产环境配置
5. **[14.5-构建与发布流程.md](./14.5-构建与发布流程.md)** - Helm Chart 构建和发布流程

## 3. 快速开始

### 3.1 开发测试（当前方式）
```bash
# 使用 Kustomize 部署
make deploy IMG=controller:latest
```

### 3.2 生产部署（规划中）
```bash
# 使用 Helm 部署
helm install novasphere ./charts/novasphere \
  --namespace novasphere-system \
  --create-namespace \
  --set image.repository=myregistry/novasphere \
  --set image.tag=v1.0.0
```

## 4. 功能对比

| 功能 | Kustomize (开发) | Helm (生产) |
|------|-----------------|------------|
| 参数化配置 | 有限 | 完整支持 |
| 版本管理 | 无 | 支持 |
| 依赖管理 | 无 | 支持 |
| 回滚 | 手动 | 自动 |
| 多环境 | 需要多个 kustomization | 单个 Chart + Values |
| 发布流程 | 简单 | 标准化 |

## 5. 实施计划

### 阶段 1: Chart 结构设计
- 创建 Helm Chart 目录结构
- 定义 Values.yaml 模板
- 转换现有 Kustomize 资源

### 阶段 2: 模板实现
- 实现 CRD 模板
- 实现 RBAC 模板
- 实现 Manager Deployment 模板
- 实现 Webhook 模板

### 阶段 3: 多环境支持
- 开发环境 Values
- 测试环境 Values
- 生产环境 Values

### 阶段 4: 构建流程
- Makefile 集成
- CI/CD 集成
- Chart 发布流程

