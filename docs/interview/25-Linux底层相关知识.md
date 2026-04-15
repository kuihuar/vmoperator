# 当前项目相关的 Linux 底层知识（面试整理）

本文从 **VM Operator / Novasphere** 实际技术栈出发，归纳需要了解的 Linux 内核与系统层概念，便于面试时把 **CRD→KubeVirt→节点** 这条链讲清楚。详细业务实现仍以 `01-整体架构概览.md`、`05`～`07`、`13.11` 等文档为准。

---

## 1. 与项目组件的对应关系

| 项目组件 | 底层主要涉及的 Linux 领域 |
|----------|---------------------------|
| **KubeVirt** | KVM/QEMU、设备虚拟化、cgroups、部分场景下的特权与安全配置 |
| **k3s / Kubernetes** | 容器运行时（containerd）、命名空间、cgroup、CNI、kubelet 与节点资源 |
| **Multus + bridge/macvlan/SR-IOV** | 虚拟网桥、VLAN、veth、MACVLAN、PCI SR-IOV、网络命名空间 |
| **NMState** | 主机网卡、路由、桥、绑定等 **网络配置在 OS 层的落地** |
| **Longhorn + CSI** | 块设备、挂载、iSCSI/NFS 等数据路径（视 Longhorn 实现与版本而定） |
| **CDI** | 临时 Pod 挂载卷、块级读写、镜像导入到卷 |

---

## 2. CPU / 内存与虚拟化（KubeVirt）

- **硬件虚拟化扩展**：Intel VT-x / AMD-V；内核模块 **`kvm`**（`kvm_intel` / `kvm_amd`）。无 KVM 时通常只能软件模拟，性能与功能受限。
- **KVM + QEMU**：KubeVirt 在节点上通过 **QEMU** 进程跑虚拟机，**KVM** 加速；需理解「**客户机**运行在由宿主机内核调度的进程里」这一层次关系。
- **CPU / 内存资源**：虚拟机 vCPU、内存最终仍受宿主机 **调度器** 与 **内存管理**（含 overcommit、NUMA 等）约束；与 Pod 的 `requests/limits` 不同层，但都会反映到节点压力上。
- **嵌套虚拟化**（了解即可）：在 VM 里再跑 VM 的场景；生产常关闭或单独规划，与边缘/ISO 交付环境相关时可被问到。

**面试话术**：「KubeVirt 把 VM 落到节点上的 QEMU/KVM；Operator 只编排 CR，真正能不能跑起来要看节点内核模块、BIOS 虚拟化开关和资源。」

---

## 3. 命名空间（Namespaces）与控制组（cgroups）

### 3.1 与 Kubernetes / 容器的关系

- **PID / NET / MNT / IPC / UTS**：Pod 内容器共享或隔离进程视图、网络栈、挂载点等；**CNI 主要在容器的网络命名空间里插网卡**。
- **cgroups（v2 为主流趋势）**：限制与统计 CPU、内存、IO 等；kubelet、容器运行时依赖 cgroups 做 **QoS、OOM、限额**。

### 3.2 与虚拟机的关系

- 虚拟机内部是 **另一套完整的客户机内核与用户态**，与宿主机命名空间无关；宿主机侧看到的是 **QEMU 进程 + 其占用的 cgroup**。
- 区分两层：**Pod/容器隔离**（K8s CRI）与 **VM 客户机隔离**（虚拟硬件 + 客户机 OS）。

---

## 4. 网络（与本项目最相关）

### 4.1 基础：虚拟以太网与 Linux 网桥

- **veth pair**：一端在 Pod 网络命名空间，一端在宿主机或网桥；是 CNI 插件最常见的接线方式。
- **Linux bridge (`bridge`)**：二层转发；Multus 配置里 **`bridge` 类型**与此直接相关。
- **VLAN（802.1q）**：内核 **`8021q`** 模块、`vlan` 子接口；Wukong `spec.networks` 中带 **VLAN** 时，底层常涉及宿主机/桥上的 VLAN 标签处理（具体由 CNI 与节点配置共同决定）。

### 4.2 多网与高性能路径

- **MACVLAN**：同网段多 MAC，少 NAT；需理解父接口、模式（bridge/private/vepa）的基本差异。
- **SR-IOV**：网卡硬件 VF 直通或半直通；涉及 **IOMMU**、PCI 设备、驱动（`vfio-pci` 等）；与「低延迟、接近线速」场景相关。

### 4.3 Multus 在系统视角下的含义

- **默认 CNI** 负责「主接口」；**Multus** 按 **NetworkAttachmentDefinition** 再挂副接口，最终在 **同一 Pod（virt-launcher）网络命名空间** 内出现多块网卡，再交给 KubeVirt 映射进 VM。
- 排障时常看：`ip link`、`ip addr`（在对应网络命名空间内）、CNI 日志、节点上桥与 VLAN 是否存在。

### 4.4 NMState

- 在 **节点 OS** 上应用期望网络状态（接口 up、桥、路由、DNS 等）；与 **「物理/宿主机网络是否就绪」** 强相关，否则 NAD/CNI 期望与真实拓扑不一致会导致 Pod/VM 起不来或不通。

### 4.5 包过滤与转发（了解）

- **iptables / nftables**：节点转发、NAT、kube-proxy 模式（iptables/ipvs）与 **Service** 可达性；VM 流量经桥/CNI 后仍可能经过宿主转发与规则。
- **`ip_forward`**：宿主机作路由器/网关时需开启。

---

## 5. 存储与块设备

### 5.1 块设备与挂载

- **块设备 vs 文件系统**：PVC 多为 **块卷**；在宿主机或容器内 **格式化、挂载** 属于另一层（CDI 导入、CSI 挂载路径由组件完成）。
- **virtio-scsi / virtio-blk**：客户机内看到的虚拟磁盘类型；与性能、热插拔能力有关（KubeVirt 磁盘配置会体现）。

### 5.2 CSI 与 Longhorn（概念层）

- **CSI**：把「挂卷 / 扩容 / 快照」标准化为节点上可执行的操作；依赖 kubelet 注册插件、节点挂载能力。
- **Longhorn**：分布式块存储；底层涉及 **副本、引擎、在节点上的数据面进程与卷暴露方式**（具体协议与版本以 Longhorn 文档为准）。面试可强调：**应用看到的是 PVC，底层是集群存储与节点块设备的组合**。

### 5.3 CDI

- 通过 **Importer Pod** 等将镜像数据写入卷；涉及 **块级读写**、临时资源调度；与 **容器存储接口、卷是否 Bound** 强相关。

---

## 6. 安全与权限（排障与面试常提）

- **Capabilities**：部分工作负载需要 `NET_ADMIN`、`SYS_ADMIN` 等（多网、网络配置类场景需谨慎评估）；KubeVirt 相关组件历史上对权限较敏感，需以实际 chart/文档为准。
- **SELinux / AppArmor**：强制访问控制可能导致 **挂载、网络、设备** 访问被拒绝；RHEL/CentOS 系环境排障常见。
- **seccomp / 特权容器**：与安全基线、合规冲突时的取舍。

---

## 7. 内核模块与简单自检（运维向）

| 模块 / 能力 | 常见用途 |
|-------------|----------|
| `kvm`, `kvm_intel` / `kvm_amd` | 硬件辅助虚拟化 |
| `bridge`, `8021q` | 桥接、VLAN |
| `tun`, `tap` | 虚拟网卡、部分 VPN/隧道场景 |
| `vfio-pci`, `mdev`（了解） | SR-IOV、GPU 等直通 |

常用命令（宿主机）：`lsmod | grep kvm`、`bridge link`、`ip -d link`、`sysctl net.ipv4.ip_forward`。

---

## 8. 与发行版 / 交付形态（k3s、ISO）

- **k3s**：精简 Kubernetes，仍依赖 **内核能力 + containerd**；节点需满足 **cgroup 驱动、内核版本** 等前置条件。
- **ISO 安装交付**（见 `16-ISO安装交付/`）：镜像定制、预装脚本与 **内核模块、驱动、固件** 是否在镜像内齐全，直接影响虚拟化与网络存储是否可用。

---

## 9. 推荐阅读顺序（本仓库内）

1. `01-整体架构概览.md` — 组件全貌  
2. `05-网络管理概述.md`、`05.1-Multus集成详解.md` — 网络类型与 NAD  
3. `06-存储管理概述.md`、`06.2-CDI集成详解.md` — 卷与导入  
4. `07-KubeVirt集成概述.md` — VM/VMI 与资源关系  
5. `13.11.x` — 控制台（VNC/SPICE/串口）在系统侧的暴露方式  

---

## 10. 一句话总结

本项目在 Linux 侧的核心是：**用 KVM/QEMU 跑 VM**，用 **网络命名空间 + Linux 网桥/VLAN/MACVLAN/SR-IOV** 做多网，用 **块设备 + CSI +（CDI 导入）** 做盘，并在 **cgroup/权限/安全模块** 约束下与 **k3s/kubelet** 协同；Operator 层负责声明式编排，**底层是否匹配 spec** 依赖节点内核与网络存储是否正确配置。
