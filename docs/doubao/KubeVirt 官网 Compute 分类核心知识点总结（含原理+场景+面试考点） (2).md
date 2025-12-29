# KubeVirt 官网 Compute 分类核心知识点总结（含原理+场景+面试考点）

## 文档说明

本文严格基于 KubeVirt 官网 Compute 分类下的核心特性，涵盖 Client Passthrough、CPU Hotplug、NUMA 等 18 个关键知识点。每个知识点均按「核心定义（官网原文核心提炼）+ 实现原理 + 适用场景 + 配置要点 + 面试考点」分层拆解，既符合官网技术规范，又突出生产实践与面试高频重点，助力快速掌握 KubeVirt 计算层核心能力。

---

# 一、CPU 相关核心特性

## 1. Dedicated CPU resources（专属 CPU 资源）

- **核心定义（官网核心）**：为虚拟机分配物理 CPU 核心，实现 CPU 资源的独占使用，避免与其他虚拟机/容器共享 CPU 导致的性能波动，保障计算密集型应用的稳定性。

- **实现原理**：基于 K8s CPU 管理器（CPU Manager）的 static 策略，将物理 CPU 核心绑定到 virt-launcher Pod，再通过 QEMU-KVM 透传给虚拟机；禁止 CPU 超分，确保虚拟机独占分配的 CPU 核心。

- **适用场景**：数据库（MySQL、PostgreSQL）、大数据计算（Spark）、实时交易系统等对 CPU 性能稳定性要求极高的场景。

- **配置要点**：① 节点需启用 CPU Manager static 策略（配置 kubelet --cpu-manager-policy=static）；② VMI 配置中指定 `cpu.dedicatedCPUPlacement: true`，并设置固定 CPU 数量（如 `cpu.cores: 4`）。

- **面试考点**：KubeVirt 专属 CPU 与共享 CPU 的区别？如何配置专属 CPU？（答题要点：核心差异在资源独占性与性能稳定性；配置需启用 CPU Manager static 策略+VMI 开启 dedicatedCPUPlacement）。

## 2. CPU Hotplug（CPU 热插拔）

- **核心定义（官网核心）**：在虚拟机运行过程中，无需关机即可动态添加/移除 CPU 核心，实现 CPU 资源的弹性扩容/缩容，适配业务负载的动态变化。

- **实现原理**：基于 QEMU-KVM 的 CPU 热插拔机制，通过 virt-api 接收 CPU 调整请求，由 virt-handler 协调 virt-launcher 执行 QEMU 命令，动态修改虚拟机的 CPU 配置；KubeVirt 负责同步 VMI CRD 配置与虚拟机实际 CPU 状态。

- **适用场景**：业务负载波动较大的场景（如电商大促前扩容 CPU、闲时缩容），避免因关机调整 CPU 导致的业务中断。

- **配置要点**：① VMI 配置中启用热插拔（`cpu.hotplug: true`）；② 预先指定 CPU 最大可扩容数量（`cpu.maximum: 8`），避免无限制扩容；③ 仅支持添加/移除整颗 CPU 核心，不支持 fractional CPU（如 0.5 核）。

- **面试考点**：KubeVirt CPU 热插拔的前提条件是什么？是否支持动态缩容？（答题要点：前提是 VMI 启用 hotplug 并配置 maximum CPU；支持动态缩容，但需确保缩容后 CPU 数量不小于当前运行所需最小核心数）。

## 3. Client Passthrough（客户端 CPU 透传）

- **核心定义（官网核心）**：一种 CPU 模式，将宿主机物理 CPU 的型号、特性完全透传给虚拟机，使虚拟机获得与物理机一致的 CPU 能力，同时避免虚拟化层对 CPU 指令的拦截与模拟。

- **实现原理**：通过 QEMU 的 `-cpu host-passthrough` 参数实现，虚拟机直接使用宿主机 CPU 的指令集，不进行任何 CPU 特性过滤；需宿主机 CPU 支持硬件虚拟化（Intel VT-x/AMD-V）。

- **适用场景**：需要使用特定 CPU 指令集的应用（如虚拟化嵌套、加密计算、高性能计算），或对 CPU 特性兼容性要求极高的遗留应用。

- **配置要点**：VMI 配置中设置 `cpu.mode: host-passthrough`；确保宿主机 CPU 支持硬件虚拟化，且未禁用相关 CPU 特性。

- **面试考点**：Client Passthrough 与其他 CPU 模式（如 host-model、custom）的区别？（答题要点：host-passthrough 完全透传 CPU 特性，性能最优但兼容性依赖宿主机；host-model 模拟宿主机 CPU 特性，兼容性更好；custom 可自定义 CPU 特性，灵活性最高）。

## 4. NUMA（非统一内存访问）

- **核心定义（官网核心）**：为虚拟机配置 NUMA 节点，使虚拟机的 CPU 核心与内存分配在同一物理 NUMA 节点上，减少跨 NUMA 节点的内存访问延迟，提升虚拟机性能。

- **实现原理**：基于宿主机 NUMA 拓扑，KubeVirt 通过 virt-controller 调度虚拟机到合适的 NUMA 节点，virt-launcher 配置 QEMU 虚拟机的 NUMA 拓扑，确保 CPU 与内存的本地化访问；支持单 NUMA 节点与多 NUMA 节点配置。

- **适用场景**：大内存、高并发的高性能应用（如虚拟化集群、大数据分析），对内存访问延迟敏感的场景。

- **配置要点**：① VMI 配置中指定 NUMA 节点数量与每个节点的 CPU/内存（如 `numa.nodes: [{ cores: 4, memory: 16Gi }]`）；② 宿主机需启用 NUMA 拓扑暴露（默认暴露）；③ 建议与专属 CPU、大页内存配合使用，性能最优。

- **面试考点**：KubeVirt 配置 NUMA 的核心目的是什么？如何保障 CPU 与内存的本地化访问？（答题要点：核心目的是减少跨 NUMA 内存访问延迟；通过配置虚拟机 NUMA 拓扑与宿主机 NUMA 拓扑匹配，结合 CPU 绑定实现本地化访问）。

---

# 二、内存相关核心特性

## 1. Hugepages support（大页内存支持）

- **核心定义（官网核心）**：为虚拟机分配大页内存（HugePages），替代默认的 4KB 小页内存，减少内存页表项数量，降低 CPU 页表管理开销，提升内存访问性能。

- **实现原理**：宿主机预先配置大页内存（如 2MB、1GB），KubeVirt 通过 VMI 配置申请大页资源，virt-launcher Pod 挂载宿主机大页内存后，通过 QEMU 分配给虚拟机；支持 2MB 和 1GB 两种大页规格。

- **适用场景**：大内存、高并发应用（如数据库、虚拟化、高性能计算），对内存访问效率要求高的场景。

- **配置要点**：① 宿主机配置大页内存（如 echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages）；② VMI 配置中指定大页规格与大小（如 `memory.hugepages.pageSize: 2Mi`，`memory: 16Gi`）；③ 大页内存大小需为页规格的整数倍。

- **面试考点**：大页内存的核心优势是什么？KubeVirt 如何配置大页内存？（答题要点：优势是减少页表项、降低 CPU 开销、提升内存访问性能；配置需宿主机预分配大页+VMI 指定大页规格与内存大小）。

## 2. Memory Hotplug（内存热插拔）

- **核心定义（官网核心）**：在虚拟机运行过程中，无需关机即可动态添加/移除内存，实现内存资源的弹性扩容/缩容，适配业务负载的动态变化。

- **实现原理**：基于 QEMU-KVM 的内存热插拔机制，通过 virt-api 接收内存调整请求，由 virt-handler 协调 virt-launcher 执行 QEMU 命令，动态为虚拟机添加/移除内存块；KubeVirt 负责同步 VMI CRD 配置与虚拟机实际内存状态。

- **适用场景**：内存需求波动较大的场景（如数据分析任务、缓存服务），避免因关机调整内存导致的业务中断。

- **配置要点**：① VMI 配置中启用热插拔（`memory.hotplug: true`）；② 预先指定内存最大可扩容数量（`memory.maximum: 32Gi`）；③ 支持添加/移除的内存块大小需为 256MB 的整数倍（官网推荐）。

- **面试考点**：Memory Hotplug 与大页内存是否兼容？动态缩容内存有什么限制？（答题要点：兼容，但需确保热插拔的内存块符合大页规格；缩容限制：缩容后内存不小于当前运行所需最小内存，且移除的内存块需为之前热添加的完整块）。

## 3. Virtual machine memory dump（虚拟机内存转储）

- **核心定义（官网核心）**：当虚拟机出现故障（如崩溃、死锁）时，将虚拟机当前的内存数据完整转储到存储中，用于后续故障分析与问题定位。

- **实现原理**：基于 QEMU 的内存转储机制，KubeVirt 通过 virtctl 触发内存转储命令，virt-launcher 调用 QEMU 接口将内存数据写入指定的 PVC 存储；支持手动触发与故障自动触发两种模式。

- **适用场景**：虚拟机故障排查场景，尤其是难以复现的崩溃问题，通过内存转储分析故障时的内存状态。

- **配置要点**：① 为虚拟机配置用于存储转储文件的 PVC（指定 `dumpVolume.name: dump-pvc`）；② 通过 `virtctl dump vm <vm-name> --to <file-path>`手动触发转储；③ 支持配置故障自动转储（需启用 virt-handler 故障监控）。

- **面试考点**：KubeVirt 虚拟机内存转储的核心作用是什么？转储文件存储在哪里？（答题要点：核心作用是故障排查，分析虚拟机崩溃时的内存状态；转储文件存储在预先配置的 PVC 中，支持后续导出分析）。

---

# 三、设备与硬件相关核心特性

## 1. Host Devices Assignment（宿主机设备分配）

- **核心定义（官网核心）**：将宿主机的物理设备（如网卡、USB 设备、PCIe 设备）直接分配给虚拟机，使虚拟机独占设备资源，提升设备访问性能。

- **实现原理**：基于 PCIe 透传技术，通过 virt-handler 检测宿主机可用设备，将设备信息暴露给 K8s API，virt-launcher 通过 libvirt 配置设备透传，使虚拟机直接与物理设备交互；支持设备热插拔（部分设备）。

- **适用场景**：需要高性能设备访问的场景（如物理网卡透传、GPU 透传、专用硬件设备）。

- **配置要点**：① 宿主机启用 IOMMU 支持（需在 BIOS 中开启，内核参数添加 intel_iommu=on/amd_iommu=on）；② VMI 配置中指定设备类型与宿主机设备标识（如 `devices.hostDevices: [{ deviceName: "eth1", type: "network" }]`）；③ 确保宿主机设备未被其他进程占用。

- **面试考点**：宿主机设备分配的前提条件是什么？与虚拟化设备相比有什么优势？（答题要点：前提是宿主机启用 IOMMU 支持；优势是设备独占、访问性能接近物理机、支持专用硬件功能）。

## 2. Mediated devices and virtual GPUs（中介设备与虚拟 GPU）

- **核心定义（官网核心）**：通过中介设备（Mediated Devices）技术，将物理 GPU 虚拟化为多个 vGPU 分配给虚拟机，实现 GPU 资源的共享使用，同时保障 GPU 访问性能。

- **实现原理**：依赖 GPU 厂商的中介设备驱动（如 NVIDIA vGPU、Intel GVT-g），宿主机通过驱动将物理 GPU 虚拟化为多个 vGPU 设备，KubeVirt 通过 Host Devices Assignment 机制将 vGPU 分配给虚拟机；支持 GPU 算力隔离与资源限制。

- **适用场景**：需要 GPU 加速的场景（如 AI 训练、图形渲染、视频编解码），多个虚拟机共享物理 GPU 资源。

- **配置要点**：① 宿主机安装 GPU 厂商驱动与中介设备驱动；② 启用 IOMMU 支持；③ VMI 配置中指定 vGPU 设备（如 `devices.mediatedDevices: [{ name: "nvidia-223", count: 1 }]`）。

- **面试考点**：Mediated devices 实现 vGPU 的优势是什么？支持哪些 GPU 厂商？（答题要点：优势是 GPU 资源共享、算力隔离、性能接近物理 GPU；支持 NVIDIA、Intel 等主流厂商，需对应驱动支持）。

## 3. Persistent TPM and UEFI state（持久化 TPM 与 UEFI 状态）

- **核心定义（官网核心）**：为虚拟机提供持久化的 TPM（可信平台模块）与 UEFI（统一可扩展固件接口）状态存储，保障虚拟机的启动安全性与状态一致性，支持虚拟机重启/迁移后状态保留。

- **实现原理**：通过 PVC 存储 TPM 与 UEFI 的状态数据，虚拟机启动时从 PVC 加载状态；迁移时同步状态数据到目标节点的 PVC；TPM 基于 swtpm（软件 TPM 模拟）或硬件 TPM 透传实现，UEFI 基于 OVMF（Open Virtual Machine Firmware）实现。

- **适用场景**：需要可信启动、加密存储的场景（如金融应用、涉密业务），要求虚拟机状态持久化的生产环境。

- **配置要点**：① 准备 OVMF 固件与 swtpm 镜像；② VMI 配置中启用 UEFI（`firmware: { uuid: "..." }`）与 TPM（`devices.tpm: { persistentVolumeClaim: { claimName: "tpm-pvc" } }`）；③ 为 TPM/UEFI 状态配置独立 PVC。

- **面试考点**：Persistent TPM 与 UEFI 的核心作用是什么？状态数据存储在哪里？（答题要点：核心作用是保障虚拟机启动安全与状态持久化；状态数据存储在 PVC 中，支持重启/迁移后保留）。

## 4. Virtual hardware（虚拟硬件）

- **核心定义（官网核心）**：KubeVirt 为虚拟机提供标准化的虚拟硬件配置，包括虚拟 CPU、内存、磁盘、网卡、显卡、固件等，支持自定义硬件规格，适配不同业务需求。

- **实现原理**：通过 VMI CRD 定义虚拟硬件参数，virt-launcher 基于 QEMU 生成对应的虚拟硬件配置，模拟物理硬件的功能；支持硬件规格的动态调整（部分硬件支持热插拔）。

- **适用场景**：所有虚拟机部署场景，根据业务需求自定义硬件规格（如低配用于测试、高配用于生产）。

- **配置要点**：① 基础配置：CPU 核心数、内存大小、磁盘数量与容量、网卡类型；② 高级配置：固件类型（BIOS/UEFI）、显卡类型（virtio、qxl）、硬件地址（MAC/UUID）；③ 自定义硬件：通过 `devices.custom` 配置自定义 QEMU 硬件参数。

- **面试考点**：KubeVirt 如何实现虚拟硬件的标准化与自定义？（答题要点：标准化通过 VMI 内置硬件配置字段实现；自定义通过 custom 字段配置 QEMU 原生参数，支持灵活适配特殊硬件需求）。

## 5. VSOCK（虚拟 SOCK 协议）

- **核心定义（官网核心）**：为虚拟机与宿主机/其他虚拟机之间提供基于 VSOCK 协议的通信方式，替代传统的网络 Socket 通信，提升通信性能，简化网络配置。

- **实现原理**：基于 virtio-vsock 设备模拟，虚拟机通过虚拟设备与宿主机的 vsock 驱动通信，无需配置 IP 地址与网络路由；支持虚拟机与宿主机、虚拟机与虚拟机之间的直接通信。

- **适用场景**：虚拟机与宿主机之间的轻量级通信场景（如监控数据上报、日志传输、agent 通信）。

- **配置要点**：① 宿主机内核支持 VSOCK（Linux 4.8+）；② VMI 配置中添加 vsock 设备（`devices.vsock: { guestCID: 3, socket: { name: "vsock-socket" } }`）；③ 宿主机与虚拟机部署支持 VSOCK 协议的应用程序。

- **面试考点**：VSOCK 与传统网络 Socket 的区别？适用场景是什么？（答题要点：区别是无需 IP 配置、通信性能更高、仅支持虚拟机与宿主机/其他虚拟机通信；适用场景是虚拟机与宿主机之间的轻量级内部通信）。

---

# 四、调度与迁移相关核心特性

## 1. Live Migration（实时迁移）

- **核心定义（官网核心）**：在虚拟机运行过程中，将虚拟机从源节点迁移到目标节点，迁移过程中业务不中断，保障服务连续性。

- **实现原理**：基于 KVM 实时迁移技术，通过 virt-controller 协调迁移流程：① 源节点与目标节点建立迁移连接；② 增量传输虚拟机内存数据（仅传输修改的脏页）；③ 传输虚拟机设备状态与网络连接；④ 切换虚拟机运行节点，断开源节点连接；底层依赖 libvirt 实现内存同步与状态迁移。

- **适用场景**：节点维护（如系统升级、硬件检修）、负载均衡（将虚拟机迁移到负载较低的节点）、容灾备份（迁移到备用节点）。

- **配置要点**：① 存储支持跨节点访问（如 Ceph RBD、NFS），禁止使用 Local PV；② 源节点与目标节点网络互通，虚拟机网络支持迁移；③ 节点硬件架构一致（如 x86_64）；④ 通过 `virtctl migrate <vm-name>` 触发迁移。

- **面试考点**：KubeVirt 实时迁移的前提条件是什么？如何保障业务不中断？（答题要点：前提是跨节点存储、网络互通、硬件架构一致；通过增量内存传输+最后一刻状态切换实现业务不中断）。

## 2. Decentralized live migration（去中心化实时迁移）

- **核心定义（官网核心）**：一种优化的实时迁移模式，迁移过程直接在源节点与目标节点之间进行，无需通过 virt-controller 中转，减少迁移延迟，提升迁移性能。

- **实现原理**：传统实时迁移由 virt-controller 协调源/目标节点的 virt-handler 完成；去中心化迁移通过源节点 virt-handler 直接与目标节点 virt-handler 建立连接，传输迁移数据，virt-controller 仅负责迁移状态监控与故障恢复，不参与数据传输。

- **适用场景**：大内存、高负载虚拟机的迁移场景，需要减少迁移延迟与集群控制平面压力。

- **配置要点**：① 启用去中心化迁移（VMI 配置中设置 `migration.decentralized: true`）；② 源节点与目标节点之间网络带宽充足；③ 其他前提条件与传统实时迁移一致。

- **面试考点**：去中心化实时迁移与传统迁移的区别是什么？优势在哪里？（答题要点：区别是迁移数据直接在源/目标节点传输，无需 controller 中转；优势是减少迁移延迟、降低控制平面压力、提升大内存虚拟机迁移性能）。

## 3. Node assignment（节点分配）

- **核心定义（官网核心）**：通过标签选择器、亲和性/反亲和性规则，将虚拟机调度到指定的节点上，实现虚拟机的精准部署与负载均衡。

- **实现原理**：复用 K8s 的调度机制，通过在 VMI/VM CRD 中配置 nodeSelector、nodeAffinity、podAffinity 等规则，virt-controller 将调度需求传递给 K8s 调度器，由 K8s 调度器完成虚拟机的节点分配。

- **适用场景**：需要将虚拟机部署到特定硬件节点（如带 GPU 的节点）、特定机房节点、或避免虚拟机集中在同一节点的场景。

- **配置要点**：① 为节点添加标签（如 `kubectl label node <node-name> hardware=gpu`）；② VMI 配置中设置节点选择规则（如 `nodeSelector: { hardware: "gpu" }`）；③ 支持亲和性规则（如 requiredDuringSchedulingIgnoredDuringExecution）。

- **面试考点**：KubeVirt 如何实现虚拟机的精准节点分配？依赖什么技术？（答题要点：通过 nodeSelector、亲和性/反亲和性规则实现；依赖 K8s 原生调度机制，virt-controller 传递调度需求）。

---

# 五、资源管理与运行策略相关核心特性

## 1. Node overcommit（节点超分）

- **核心定义（官网核心）**：允许节点分配的虚拟机 CPU/内存资源总和超过节点的物理资源上限，提高节点资源利用率；通过超分策略控制超分比例，避免资源过度抢占导致的性能下降。

- **实现原理**：基于 K8s 的资源超分机制，通过配置节点的 CPU/内存超分比例（如 CPU 超分 2:1、内存超分 1.5:1），K8s 调度器根据超分后的可用资源分配虚拟机；KubeVirt 支持为不同虚拟机配置不同的超分优先级，保障核心业务的资源需求。

- **适用场景**：虚拟机负载波动较大、资源利用率较低的场景（如开发/测试环境、非核心业务生产环境）。

- **配置要点**：① 配置 K8s 资源超分策略（通过 kubelet 参数或调度器配置）；② 为 VMI 配置合理的 requests/limits（如 limits.cpu: 2, requests.cpu: 1，超分比例 2:1）；③ 核心业务建议禁用超分，保障性能稳定。

- **面试考点**：Node overcommit 的核心优势与风险是什么？如何规避风险？（答题要点：优势是提高资源利用率；风险是资源过度抢占导致性能下降；规避方式是合理设置超分比例、为核心业务配置高优先级、监控节点资源使用率）。

## 2. Resources requests and limits（资源请求与限制）

- **核心定义（官网核心）**：为虚拟机配置 CPU/内存的请求量（requests）与限制量（limits），实现资源的精细化管理；requests 是虚拟机启动所需的最小资源，limits 是虚拟机可使用的最大资源。

- **实现原理**：复用 K8s 的资源管理机制，VMI 的 requests/limits 直接映射为 virt-launcher Pod 的 requests/limits，K8s 调度器根据 requests 分配节点资源，kubelet 根据 limits 限制 Pod 的资源使用；KubeVirt 确保虚拟机的资源使用不超过 limits 限制。

- **适用场景**：所有虚拟机部署场景，尤其是多租户集群、混合负载集群，需要实现资源隔离与公平分配。

- **配置要点**：① VMI 配置中指定 resources.requests 与 resources.limits（如 `resources: { requests: { cpu: "1", memory: "4Gi" }, limits: { cpu: "2", memory: "8Gi" } }`）；② requests 建议设置为虚拟机运行所需的最小资源，避免资源浪费；③ limits 建议根据业务峰值需求设置，避免资源过度占用。

- **面试考点**：KubeVirt 虚拟机的 resources.requests 与 limits 作用是什么？与 Pod 的资源配置有什么关系？（答题要点：requests 是调度最小资源，limits 是最大使用资源；虚拟机的资源配置直接映射为 virt-launcher Pod 的配置，由 K8s 负责资源调度与限制）。

## 3. Run Strategies（运行策略）

- **核心定义（官网核心）**：定义虚拟机的运行策略，控制虚拟机的启动、重启、停止行为，实现虚拟机生命周期的自动化管理。

- **实现原理**：通过 VM CRD 的 runStrategy 字段配置策略，virt-controller 根据策略监控虚拟机状态，自动执行对应的生命周期操作；支持多种策略：Always（始终运行，故障自动重启）、RerunOnFailure（故障时重启一次）、Manual（手动控制，不自动重启）、Halted（停止状态，不自动启动）。

- **适用场景**：根据业务需求选择策略（如核心业务用 Always 保障高可用，测试虚拟机用 Manual 手动控制）。

- **配置要点**：VM 配置中设置 `runStrategy: Always`（其他策略同理）；策略仅作用于 VM 控制的 VMI，手动创建的 VMI 不受策略影响。

- **面试考点**：KubeVirt 有哪些 Run Strategies？核心作用是什么？（答题要点：包括 Always、RerunOnFailure、Manual、Halted；核心作用是自动化管理虚拟机生命周期，根据业务需求保障高可用或手动控制）。

---

# 六、Compute 核心知识点总结（面试高频考点梳理）

## 1. 核心能力维度

KubeVirt Compute 层核心围绕「资源管理（CPU/内存）、硬件适配（设备透传/GPU）、调度迁移（实时迁移/节点分配）、运行保障（高可用/故障排查）」四大维度，所有特性均基于 K8s 调度与资源管理机制，结合 QEMU-KVM 虚拟化能力实现。

## 2. 面试高频考点清单

1. CPU 相关：专属 CPU 配置、CPU Hotplug 前提、Client Passthrough 模式区别、NUMA 优化原理。

2. 内存相关：大页内存配置与优势、Memory Hotplug 限制、内存转储的作用与存储位置。

3. 设备相关：宿主机设备分配前提（IOMMU）、vGPU 实现原理、Persistent TPM/UEFI 的作用。

4. 迁移相关：实时迁移前提条件、去中心化迁移优势、业务不中断的实现原理。

5. 资源与策略：requests/limits 作用、Node overcommit 风险与规避、Run Strategies 分类与适用场景。

## 4. 补充面试题（含答题要点）

1. **问题**：KubeVirt 中启用 Dedicated CPU resources 时，为什么必须配置 K8s CPU Manager 的 static 策略？
**答题要点**：因为 static 策略能将物理 CPU 核心独占分配给 virt-launcher Pod，避免 CPU 核心被其他 Pod 共享；而默认的 none 策略仅做资源限制，不保证 CPU 独占，无法满足专属 CPU 对性能稳定性的要求。配置后 KubeVirt 可通过 virt-launcher 将独占的 CPU 核心透传给虚拟机，禁止超分，保障计算密集型应用的性能。

2. **问题**：NUMA 配置与大页内存、专属 CPU 配合使用的核心原因是什么？
**答题要点**：三者配合可实现“CPU-内存-硬件”的本地化访问闭环：① NUMA 确保 CPU 与内存分配在同一物理 NUMA 节点，减少跨节点内存访问延迟；② 大页内存减少内存页表开销，提升内存访问效率；③ 专属 CPU 避免 CPU 核心切换，保障计算稳定性。三者协同可最大化提升虚拟机的高性能计算能力，适配大内存、高并发场景。

3. **问题**：KubeVirt 实现 Memory Hotplug 时，为什么要求热插拔的内存块大小为 256MB 的整数倍？
**答题要点**：这是 KubeVirt 基于 QEMU-KVM 内存热插拔机制的标准化设计：① QEMU 对热插拔内存块有最小粒度要求，256MB 是官网验证的兼容粒度，可避免内存块分配冲突；② 标准化粒度便于 KubeVirt 同步 VMI CRD 配置与虚拟机实际内存状态，简化内存扩容/缩容的管理逻辑；③ 确保不同节点、不同版本 QEMU 环境下的兼容性，降低生产环境部署风险。

4. **问题**：宿主机设备分配中 IOMMU 的核心作用是什么？如果未启用 IOMMU 会有什么影响？
**答题要点**：① IOMMU 核心作用是实现设备 I/O 地址的隔离与重映射，防止虚拟机通过透传设备直接访问宿主机物理内存，保障宿主机与其他虚拟机的安全；同时支持设备中断重定向，提升设备 I/O 性能。② 未启用 IOMMU 会导致：无法实现设备透传（KubeVirt 会拒绝调度）；即使强制透传，虚拟机可能越权访问宿主机资源，引发安全风险；设备 I/O 中断无法精准定向，性能大幅下降。

5. **问题**：Decentralized live migration 相比传统迁移，在控制平面故障时会有什么影响？
**答题要点**：① 迁移过程中控制平面故障：去中心化迁移不受影响，因为数据传输直接在源/目标节点的 virt-handler 之间进行，virt-controller 仅监控状态，不参与数据传输；传统迁移会因失去 controller 协调而中断。② 迁移完成后状态同步：控制平面故障会导致 VMI 状态无法及时更新到 K8s API，但虚拟机实际已迁移成功；待控制平面恢复后，virt-controller 会同步最新状态，不影响业务运行。

6. **问题**：KubeVirt 中 Run Strategies 的 Always 与 RerunOnFailure 策略的核心区别是什么？分别适用于什么场景？
**答题要点**：① 区别：Always 策略会确保虚拟机始终运行，无论故障次数（如节点重启、虚拟机崩溃后均自动重启）；RerunOnFailure 仅在首次故障时重启一次，若重启后再次故障则不再干预。② 场景：Always 适用于核心业务（如数据库、交易系统），需最高级别的高可用；RerunOnFailure 适用于非核心业务（如测试环境虚拟机、临时任务），避免因持续故障导致资源浪费。

7. **问题**：Persistent TPM 与 UEFI 状态为什么需要通过 PVC 存储？直接存储在宿主机有什么问题？
**答题要点**：① 用 PVC 存储的原因：PVC 支持跨节点访问，可保障虚拟机迁移后 TPM/UEFI 状态的一致性；PVC 具备持久化能力，避免宿主机故障导致状态丢失；契合 K8s 云原生存储生态，便于统一管理与备份。② 存储在宿主机的问题：虚拟机迁移后无法访问源节点的状态数据，导致启动失败；宿主机故障会直接丢失状态，虚拟机无法恢复可信启动环境；不支持集群级高可用部署，不符合生产环境要求。

8. **问题**：VSOCK 相比传统网络 Socket，在虚拟机与宿主机通信时的核心优势是什么？为什么不需要配置 IP 地址？
**答题要点**：① 核心优势：通信性能更高（基于 virtio-vsock 虚拟设备，绕过 TCP/IP 协议栈，减少网络开销）；配置更简单（无需设置 IP、路由、防火墙规则）；安全性更强（仅支持虚拟机与宿主机/其他虚拟机内部通信，不暴露到外部网络）。② 无需 IP 的原因：VSOCK 基于“上下文 ID（CID）+ 端口”标识通信双方，虚拟机的 CID 由 KubeVirt 分配，宿主机 CID 固定为 2，通过 virtio-vsock 设备直接建立虚拟通道，无需 IP 地址进行网络寻址。

## 3. 核心设计理念

官网 Compute 分类特性的核心设计理念：**复用 K8s 生态能力，适配虚拟化场景需求**——通过 CRD 定义虚拟化资源，借助 K8s 调度、资源管理、存储/网络生态，实现虚拟机的云原生管理；同时保留 QEMU-KVM 虚拟化的核心能力（如设备透传、实时迁移），兼顾性能与兼容性。
> （注：文档部分内容可能由 AI 生成）