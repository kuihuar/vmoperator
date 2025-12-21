# VM Operator 文档中心

欢迎来到 VM Operator 文档中心！这里包含了项目的完整文档。

## 📚 文档导航

### 入门文档

- **[快速开始指南](QUICKSTART.md)** ⭐ 推荐新手阅读
  - 环境准备
  - 组件安装
  - 第一个虚拟机

### 核心文档

- **[开发文档](DEVELOPMENT.md)** 📖 完整开发指南
  - 项目概述
  - 技术架构
  - 开发步骤
  - 集成方案
  - 测试方案
  - 故障排查

- **[完整组件清单](COMPONENTS.md)** 📦 所有需要的组件
  - 核心组件
  - 依赖组件
  - 可选组件
  - 安装检查清单

- **[架构设计](ARCHITECTURE.md)** 🏗️ 系统架构详解
  - 整体架构
  - 核心组件
  - 数据流
  - 扩展点
  - 性能优化

- **[API 文档](API.md)** 📋 API 详细说明
  - CRD 定义
  - 字段说明
  - 使用示例
  - 最佳实践

- **[kubebuilder init 参数说明](KUBEBUILDER_INIT.md)** 🔧 初始化参数详解
  - domain 参数说明
  - repo 参数说明
  - 参数选择建议
  - 实际使用示例

### Longhorn 存储文档

- **[k3s 安装 Longhorn 常见问题汇总](K3S_LONGHORN_ISSUES.md)** ⚠️ **强烈推荐阅读**
  - 14 个常见问题及解决方案
  - 安装前、安装中、安装后、运行时问题
  - 快速诊断和修复流程
  - 最佳实践建议

- **[Longhorn 安装指南](LONGHORN_INSTALLATION_GUIDE.md)** 📦 完整安装指南
  - 前置要求
  - kubectl 和 Helm 两种安装方法
  - 验证和故障排查

- **[Longhorn 重新安装指南](LONGHORN_REINSTALL_GUIDE.md)** 🔄 卸载和重新安装
  - 完整卸载流程
  - 重新安装步骤
  - 版本选择建议

- **[Longhorn 故障排查指南](FIX_LONGHORN_ISSUES.md)** 🔍 故障排查
  - Manager CrashLoopBackOff
  - driver-deployer 初始化问题
  - 磁盘配置问题

## 🚀 快速链接

### 按角色查找

**开发者**
1. 阅读 [快速开始指南](QUICKSTART.md) 搭建环境
2. 阅读 [开发文档](DEVELOPMENT.md) 了解开发流程
3. 阅读 [架构设计](ARCHITECTURE.md) 理解系统设计
4. 阅读 [API 文档](API.md) 了解资源定义

**运维人员**
1. 阅读 [快速开始指南](QUICKSTART.md) 了解安装步骤
2. 阅读 [开发文档 - 部署指南](DEVELOPMENT.md#部署指南) 了解部署流程
3. 阅读 [k3s 安装 Longhorn 常见问题汇总](K3S_LONGHORN_ISSUES.md) 了解 Longhorn 问题处理
4. 阅读 [开发文档 - 故障排查](DEVELOPMENT.md#故障排查) 了解问题处理

**架构师**
1. 阅读 [架构设计](ARCHITECTURE.md) 了解整体架构
2. 阅读 [开发文档 - 技术架构](DEVELOPMENT.md#技术架构) 了解技术选型
3. 阅读 [开发文档 - 集成方案](DEVELOPMENT.md#集成方案) 了解集成细节

## 📖 文档结构

```
docs/
├── README.md           # 本文档（文档索引）
├── QUICKSTART.md       # 快速开始指南
├── DEVELOPMENT.md      # 开发文档（核心）
├── COMPONENTS.md       # 完整组件清单
├── ARCHITECTURE.md     # 架构设计文档
└── API.md              # API 详细说明
```

## 🔍 常见问题

### 我应该从哪里开始？

- **新手**: 从 [快速开始指南](QUICKSTART.md) 开始
- **有经验的开发者**: 直接阅读 [开发文档](DEVELOPMENT.md)
- **架构师**: 先看 [架构设计](ARCHITECTURE.md)

### 如何查找特定信息？

- **API 使用**: 查看 [API 文档](API.md)
- **环境搭建**: 查看 [快速开始指南](QUICKSTART.md)
- **开发流程**: 查看 [开发文档](DEVELOPMENT.md)
- **系统设计**: 查看 [架构设计](ARCHITECTURE.md)
- **Longhorn 问题**: 查看 [k3s 安装 Longhorn 常见问题汇总](K3S_LONGHORN_ISSUES.md) ⭐
- **问题排查**: 查看 [开发文档 - 故障排查](DEVELOPMENT.md#故障排查)

### 文档有更新吗？

所有文档都会随着项目发展持续更新。建议定期查看最新版本。

## 📝 文档贡献

如果您发现文档有错误或需要改进，欢迎：

1. 提交 Issue 描述问题
2. 提交 Pull Request 直接改进文档
3. 在讨论区提出建议

## 🔗 相关资源

- [项目 README](../README.md)
- [KubeVirt 官方文档](https://kubevirt.io/user-guide/)
- [Multus CNI 文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NMState Operator 文档](https://nmstate.github.io/)
- [kubebuilder 教程](https://book.kubebuilder.io/)

---

**提示**: 建议按顺序阅读文档，以获得最佳学习体验。

