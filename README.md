# VM Operator - 定制虚拟机管理平台

基于 Kubernetes 生态构建的定制虚拟机管理平台，通过统一的 CRD 接口简化虚拟机的创建、配置和管理。

## 项目简介

VM Operator 是一个 Kubernetes Operator，用于在 k3s 集群上管理虚拟机。它集成了以下技术栈：

- **k3s**: 轻量级 Kubernetes 发行版
- **KubeVirt**: 在 Kubernetes 上运行虚拟机的 Operator
- **CDI**: 容器化数据导入工具，用于从镜像创建虚拟机磁盘
- **Multus CNI**: 多网络接口支持
- **NMState Operator**: 节点网络配置管理
- **华美存储**: 分布式存储 CSI 驱动

## 核心功能

- ✅ **统一虚拟机管理接口**: 通过自定义 CRD 提供简洁的虚拟机配置方式
- ✅ **多网络支持**: 支持虚拟机配置多个网络接口（管理网、业务网等）
- ✅ **灵活存储管理**: 集成华美存储，支持多种存储类型和配置
- ✅ **网络自动化配置**: 自动配置节点网络（VLAN、桥接、SR-IOV等）
- ✅ **高可用支持**: 支持虚拟机高可用、反亲和性等策略

## 快速开始

### 前置要求

- k3s >= 1.24
- CDI >= 1.57 (Containerized Data Importer)
- KubeVirt >= 0.58
- Multus CNI >= 3.9
- NMState Operator >= 0.73
- 华美存储 CSI 驱动

### 安装

```bash
# 1. 克隆项目
git clone https://github.com/your-org/vmoperator.git
cd vmoperator

# 2. 安装 CRD
make install

# 3. 部署 Operator
make deploy

# 4. 验证安装
kubectl get pods -n vmoperator-system
```

### 使用示例

```yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: web-server-01
spec:
  cpu: 4
  memory: 8Gi
  networks:
    - name: mgmt
      type: bridge
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
  disks:
    - name: system
      size: 80Gi
      storageClassName: huamei-sc-ssd
      boot: true
```

```bash
# 创建虚拟机
kubectl apply -f examples/web-server.yaml

# 查看状态
kubectl get vmprofile web-server-01

# 查看详情
kubectl describe vmprofile web-server-01
```

## 文档

- [开发文档](docs/DEVELOPMENT.md) - 完整的开发指南和架构说明
- [API 文档](docs/API.md) - VirtualMachineProfile API 详细说明

## 项目结构

```
vmoperator/
├── api/                    # API 定义
├── config/                 # 部署配置
├── controllers/            # 控制器
├── pkg/                    # 内部包
│   ├── kubevirt/          # KubeVirt 集成
│   ├── network/           # 网络管理
│   └── storage/           # 存储管理
└── docs/                   # 文档
```

## 开发

```bash
# 运行测试
make test

# 构建镜像
make docker-build IMG=your-registry/vmoperator:latest

# 部署到集群
make deploy IMG=your-registry/vmoperator:latest
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[待定]

## 相关链接

- [KubeVirt 文档](https://kubevirt.io/user-guide/)
- [Multus CNI 文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NMState Operator 文档](https://nmstate.github.io/)
- [kubebuilder 教程](https://book.kubebuilder.io/)
