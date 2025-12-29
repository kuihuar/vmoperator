# Kubevirt 网络体系详解（Flannel+CoreDNS+Multus 环境）

本文聚焦 Kubevirt 虚拟化场景下的网络体系，详细拆解 **宿主机双网卡**、**K8s 集群网络（Flannel+CoreDNS）** 与 **Kubevirt 虚拟机网络（Multus 多网卡）** 的层级关系、组件交互逻辑、数据流向，并通过流程图直观呈现核心关联，为部署、运维及问题排查提供参考。

## 一、核心网络组件定位与分工

在 Flannel+CoreDNS+Multus 环境中，各网络组件各司其职，形成“底层承载-中间桥梁-上层扩展”的三层架构，核心定位如下表所示：

|网络层级|核心组件|核心功能|核心特点|
|---|---|---|---|
|底层承载层|宿主机双网卡（物理网卡，如 eth0、eth1）|提供物理网络载体，承载所有上层网络流量；通常分工为管理网+业务网|物理层面转发，无软件虚拟化开销，是所有网络的基础|
|中间桥梁层|Flannel（CNI）、CoreDNS（DNS 服务）|Flannel 构建 K8s 集群统一 Pod 网络平面；CoreDNS 提供全集群域名解析|实现集群内资源互联互通，为上层虚拟机网络提供基础依赖|
|上层扩展层|Multus（多网络 CNI）、Macvlan/SR-IOV（辅助网络插件）|基于 Flannel 主网络扩展多网卡能力，为虚拟机提供多网络平面接入|支持虚拟机同时接入集群网和业务网，适配复杂业务场景|
## 二、网络层级深度拆解（从底层到上层）

### 1. 底层承载：宿主机双网卡的典型分工

宿主机的两个物理网卡是整个网络体系的“基石”，所有上层软件定义网络（SDN）的流量最终都会通过这两个网卡转发。在 K8s+Kubevirt 生产环境中，双网卡通常采用“功能隔离”的分工模式，具体如下：

- **网卡 1（管理网网卡，如 eth0）**

    - 核心职责：承载宿主机管理流量、K8s 控制平面流量、Flannel 集群网流量

    - 具体承载内容：
                

        - 宿主机自身管理：SSH 登录、宿主机间基础通信、系统监控（如 Prometheus 采集宿主机指标）

        - K8s 控制平面交互：kube-apiserver、kube-scheduler、kube-controller-manager 等组件间的通信

        - Flannel 隧道流量：Flannel 采用 VXLAN 模式（默认）时，跨节点 Pod/虚拟机的流量会被封装为 VXLAN 数据包，通过该网卡在宿主机间传输

    - IP 配置：通常配置静态 IP（如 192.168.0.10/24），接入企业管理网络

- **网卡 2（业务网网卡，如 eth1）**

    - 核心职责：承载用户业务流量，为虚拟机辅助网卡提供物理网络接入

    - 具体承载内容：
                

        - 虚拟机业务流量：通过 Multus 扩展的辅助网卡（Macvlan/SR-IOV），将虚拟机业务流量直接接入物理业务网络

        - 集群对外业务出口：部分场景下，可作为集群内业务服务（如虚拟机对外提供的应用服务）的出口网卡

    - IP 配置：配置静态 IP（如 10.0.0.10/24），接入企业业务网络，与业务服务器、终端等设备在同一二层网络

注意：双网卡的分工可根据实际需求调整，核心原则是“流量隔离”——避免管理流量、集群流量与业务流量抢占带宽，提升网络稳定性。

### 2. 中间桥梁：K8s 集群网络（Flannel+CoreDNS）的核心作用

Flannel 和 CoreDNS 共同构建了 K8s 集群的“基础网络能力”，也是 Kubevirt 虚拟机能够融入集群的关键，两者协同为上层网络提供支撑。

#### （1）Flannel：构建统一的集群网络平面

Flannel 是 K8s 最常用的网络插件之一，核心目标是解决“跨节点 Pod 互联互通”问题，其工作原理与在 Kubevirt 网络中的作用如下：

- **核心工作原理（VXLAN 模式）**：
        

    1. Flannel 为 K8s 集群分配一个全局 Pod 网段（如 10.244.0.0/16），并为每个节点分配一个子网段（如 node1：10.244.1.0/24，node2：10.244.2.0/24）。

    2. 每个节点上运行 flanneld 进程，通过 etcd 同步全集群的节点子网信息和节点 IP（宿主机 eth0 IP）。

    3. 当跨节点 Pod/虚拟机通信时，Flannel 会将数据包封装为 VXLAN 格式，通过宿主机 eth0 发送到目标节点；目标节点接收后解封装，转发到对应 Pod/虚拟机。

- **在 Kubevirt 网络中的核心作用**：
        

    - 为虚拟机提供“主网卡”网络：Kubevirt 虚拟机运行在 virt-launcher Pod 中，该 Pod 会接入 Flannel 网络，因此虚拟机的主网卡默认继承 Flannel 网段 IP（如 10.244.1.100），实现与集群内 Pod、Service 的互联互通。

    - 构建跨节点虚拟机通信基础：不同节点上的虚拟机，可通过 Flannel VXLAN 隧道实现跨节点通信，无需额外配置路由。

#### （2）CoreDNS：全集群统一 DNS 解析

CoreDNS 以 Pod 形式部署在 K8s 集群中，是集群内的“DNS 服务器”，其核心作用是为 Pod、Service、虚拟机等资源提供域名解析，支撑跨组件通信。

- **核心解析能力**：
        

    - 解析 Service 域名：将 Service 名称（如 nginx-service.default.svc.cluster.local）解析为对应的 ClusterIP，方便 Pod/虚拟机通过 Service 访问后端应用。

    - 解析 Pod 域名：将 Pod 的 FQDN（如 pod-xxx.default.pod.cluster.local）解析为 Pod IP，支持 Pod 间直接通过域名通信。

    - 转发外部域名：若集群配置了上游 DNS，CoreDNS 可转发集群外域名（如 www.baidu.com）的解析请求，实现 Pod/虚拟机访问互联网。

- **与 Kubevirt 虚拟机的关联**：
        

    - 虚拟机的 DNS 配置继承自 virt-launcher Pod：virt-launcher Pod 的 /etc/resolv.conf 中会配置 CoreDNS 的 Service IP（通常是 10.96.0.10），因此虚拟机的 DNS 服务器默认指向 CoreDNS。

    - 支持虚拟机通过域名访问集群资源：虚拟机可直接通过 Service 域名访问 K8s 集群内的应用（如访问数据库 Service：mysql-service.default），无需记忆具体 IP。

### 3. 上层扩展：Kubevirt Multus 多网卡技术

Multus 是一款“多网络 CNI 插件”，本身不提供网络转发能力，核心作用是“聚合”多个 CNI 插件（如 Flannel、Macvlan、SR-IOV 等），为 Kubevirt 虚拟机提供多网卡、多网络平面接入能力，满足复杂业务场景需求。

#### （1）Multus 工作原理

Multus 通过 CRD（NetworkAttachmentDefinition）定义多个网络平面，当创建虚拟机时，通过在 VirtualMachineInstance（VMI）CR 中指定多个网络，实现多网卡挂载：

1. 管理员通过 NetworkAttachmentDefinition CR 定义网络：如“flannel-network”（关联 Flannel CNI）、“macvlan-business-network”（关联 Macvlan CNI）。

2. 创建 VMI 时，在 spec.domain.devices.interfaces 中指定多个网络，每个网络对应一个网卡。

3. Multus 调用对应的 CNI 插件为 VMI 配置多个网络接口，每个接口接入不同的网络平面。

#### （2）虚拟机双网卡典型配置（集群网+业务网）

结合宿主机双网卡分工，虚拟机通常配置“主网卡+辅助网卡”，分别接入集群网和业务网，具体配置与作用如下：

- **主网卡（接入 Flannel 集群网）**：
        

    - 网络来源：关联 Flannel CNI 插件，通过 Multus 作为“主网络”配置。

    - IP 范围：与 Flannel Pod 网段一致（如 10.244.1.0/24）。

    - 核心作用：与 K8s 集群内的 Pod、Service 通信；通过 Flannel 隧道与其他节点的虚拟机/Pod 通信；通过集群网关访问互联网。

    - 依赖宿主机网卡：宿主机 eth0（Flannel 隧道流量载体）。

- **辅助网卡（接入物理业务网）**：
        

    - 网络来源：关联 Macvlan 或 SR-IOV CNI 插件，通过 Multus 作为“辅助网络”配置。

    - IP 范围：与宿主机 eth1 网段一致（如 10.0.0.0/24），属于物理业务网 IP。

    - 核心作用：直接与物理业务网络中的设备（如业务服务器、终端、IoT 设备）通信，承载核心业务流量。

    - 依赖宿主机网卡：宿主机 eth1（直接承载业务流量，无 VXLAN 封装开销）。

补充：Macvlan 与 SR-IOV 选型建议——Macvlan 配置简单，无需硬件支持，适合普通业务场景；SR-IOV 需网卡支持，可将物理网卡的虚拟功能（VF）直接分配给虚拟机，性能接近物理机，适合高带宽、低延迟场景（如工业控制、高清视频传输）。

## 三、核心数据流向解析（关键通信场景）

以下梳理 4 个典型通信场景的数据流，清晰呈现各网络组件的协同过程：

### 1. 场景 1：虚拟机 ↔ K8s 集群内 Pod

通信双方：虚拟机（主网卡，10.244.1.100） ↔ 同节点 Pod（10.244.1.200）

1. 虚拟机发送数据包，目标 IP 为 10.244.1.200，通过主网卡（Flannel 网段）发送到 virt-launcher Pod 网络命名空间。

2. Flannel CNI 插件在节点内维护本地 Pod 路由表，直接将数据包转发到目标 Pod 的网络命名空间。

3. 目标 Pod 接收数据包并处理，响应数据包按原路径返回虚拟机。

若为跨节点 Pod 通信，数据流为：虚拟机主网卡 → virt-launcher Pod → 宿主机 eth0 → Flannel VXLAN 隧道 → 目标节点 eth0 → 目标节点 Flannel 解封装 → 目标 Pod。

### 2. 场景 2：虚拟机 ↔ 物理业务网设备

通信双方：虚拟机（辅助网卡，10.0.0.20） ↔ 业务服务器（10.0.0.100）

1. 虚拟机通过辅助网卡发送业务数据包，目标 IP 为 10.0.0.100。

2. 若使用 Macvlan 插件：数据包直接通过宿主机 eth1 发送到物理网络（Macvlan 虚拟网卡与宿主机 eth1 在同一二层网络）。

3. 若使用 SR-IOV 插件：数据包直接通过分配的 VF 网卡发送到物理网络，无需宿主机内核转发。

4. 物理业务网中的业务服务器接收数据包并响应，响应数据包按原路径返回虚拟机辅助网卡。

### 3. 场景 3：虚拟机 ↔ 互联网

通信双方：虚拟机（主网卡，10.244.1.100） ↔ 互联网服务器（如 www.baidu.com）

1. 虚拟机发送访问请求，目标域名为 www.baidu.com，先通过 CoreDNS 解析域名（CoreDNS 地址：10.96.0.10）。

2. CoreDNS 返回互联网服务器 IP，虚拟机生成数据包，通过主网卡发送到 virt-launcher Pod。

3. 数据包经 Flannel 网络转发到宿主机 eth0，通过集群网关（通常是宿主机网关）进行 NAT 转换（将 Pod 网段 IP 转换为宿主机 eth0 公网/内网 IP）。

4. 转换后的数据包通过企业网络出口访问互联网服务器，响应数据包按原路径返回虚拟机。

### 4. 场景 4：跨节点虚拟机 ↔ 虚拟机

通信双方：node1 虚拟机（主网卡 10.244.1.100） ↔ node2 虚拟机（主网卡 10.244.2.200）

1. node1 虚拟机发送数据包，目标 IP 为 10.244.2.200，通过主网卡发送到 virt-launcher Pod。

2. Flannel 将数据包封装为 VXLAN 格式，外层 IP 为 node1 宿主机 eth0 IP（192.168.0.10），目标 IP 为 node2 宿主机 eth0 IP（192.168.0.20）。

3. VXLAN 数据包通过宿主机 eth0 发送到 node2 宿主机 eth0。

4. node2 宿主机上的 flanneld 进程解封装 VXLAN 数据包，得到原始数据包，转发到 node2 虚拟机的 virt-launcher Pod，最终送达虚拟机。

## 四、网络体系关联流程图

以下通过流程图直观呈现宿主机双网卡、Flannel+CoreDNS、Multus 及虚拟机的层级关联和数据转发路径：

```mermaid

graph TD
    subgraph 宿主机 Node1
        A[物理网卡 eth0（管理网+集群网）] --> A1[flanneld 进程VXLAN 隧道封装]
        B[物理网卡 eth1（业务网）] --> B1[Macvlan/SR-IOV 插件]
        A1 --> C[virt-launcher Pod 网络命名空间]
        B1 --> C
        C --> D[Kubevirt 虚拟机主网卡（10.244.1.100）]
        C --> E[Kubevirt 虚拟机辅助网卡（10.0.0.20）]
    end
    
    subgraph 宿主机 Node2
        F[物理网卡 eth0（管理网+集群网）] --> F1[flanneld 进程VXLAN 隧道解封装]
        G[物理网卡 eth1（业务网）] --> G1[Macvlan/SR-IOV 插件]
        F1 --> H[virt-launcher Pod 网络命名空间]
        G1 --> H
        H --> I[Kubevirt 虚拟机主网卡（10.244.2.200）]
        H --> J[Kubevirt 虚拟机辅助网卡（10.0.0.30）]
    end
    
    subgraph K8s 集群核心组件
        K[CoreDNS Pod（10.96.0.10）]
        L[etcd（存储网络配置）]
    end
    
    subgraph 外部网络
        M[K8s 集群内 Pod（10.244.1.200）]
        N[物理业务服务器（10.0.0.100）]
        O[互联网服务器（www.baidu.com）]
    end
    
    %% 数据流关联
    D --> K[CoreDNS]  %% 虚拟机主网卡解析域名
    E --> N[业务服务器]  %% 虚拟机辅助网卡访问业务网
    D --> M[集群内 Pod]  %% 虚拟机主网卡访问 Pod
    D --> A1 --> F1 --> I  %% 跨节点虚拟机主网卡通信
    K --> O[互联网服务器]  %% CoreDNS 转发外部解析
    A1 --> L[etcd]  %% flanneld 同步网络配置
    F1 --> L[etcd]
    D --> A1 --> O  %% 虚拟机访问互联网
    
```
流程图说明：
1. 实线箭头：数据转发路径；虚线箭头：配置同步/依赖关系。
2. 清晰呈现“虚拟机双网卡分别接入集群网和业务网”“跨节点通过 Flannel VXLAN 隧道通信”“CoreDNS 为全集群提供解析”的核心逻辑。

## 五、部署与运维关键注意事项

1. **宿主机网卡配置**：确保双网卡 IP 不在同一网段，避免路由冲突；关闭网卡的防火墙规则（如 iptables、firewalld），或放行 Flannel VXLAN 端口（默认 8472/UDP）、业务网端口。

2. **Flannel 配置优化**：生产环境建议使用 Host-GW 模式（需宿主机间二层互通）替代默认 VXLAN 模式，减少封装开销；通过 etcd 配置 Flannel 网段时，避免与业务网、管理网网段重叠。

3. **Multus 网络定义**：创建 NetworkAttachmentDefinition 时，需明确指定 CNI 插件类型（flannel、macvlan 等）和对应的网卡信息（如 Macvlan 需指定 master 为 eth1）。

4. **虚拟机网卡配置验证**：创建 VMI 后，可通过 `virtctl console <vmi-name>` 登录虚拟机，执行 `ip addr` 验证双网卡 IP 配置；通过 `ping` 测试与 Pod、业务服务器、互联网的连通性。

5. **DNS 解析问题排查**：若虚拟机无法解析域名，检查 virt-launcher Pod 的 /etc/resolv.conf 是否配置 CoreDNS IP；检查 CoreDNS Pod 是否正常运行；通过 `nslookup <service-name> 10.96.0.10` 测试解析。

## 六、总结

Kubevirt 网络体系的核心是“分层协作、流量隔离”：宿主机双网卡提供底层物理承载，Flannel+CoreDNS 构建集群基础网络能力，Multus 实现上层多网卡扩展。这种架构既保证了虚拟机与 K8s 集群的深度融合，又通过多网卡设计适配了复杂业务场景的网络需求。部署和运维时，需重点关注网段规划、网卡分工、CNI 插件配置及连通性验证，确保整个网络体系稳定高效运行。
> （注：文档部分内容可能由 AI 生成）