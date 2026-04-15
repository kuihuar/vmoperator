# Electron 桌面如何访问并连接虚拟机（原理）

本文说明在本项目相关架构下（API Gateway、独立 API Service、KubeVirt），**Electron 桌面端**如何访问某台虚拟机，以及数据与控制路径上的**原理**。可与 `18-多客户端API Service架构方案.md`、`22-流式数据传输方案详解.md`、`23-网关流式数据代理详解.md`、`13.11.x` 控制台章节对照阅读。

---

## 1. Electron 本身不直接连 VM

Electron = **Chromium（渲染 UI）+ Node（系统能力）**。访问虚拟机时，与 Web 前端一样，主要走 **HTTPS / WSS**，并不会因为“桌面壳”就多出一条特殊通道。

与浏览器的常见差异包括：

- 可使用 Node 的 **`ws`** 等库建立 WebSocket；
- Token 可放在 **系统安全存储**（而非仅 `localStorage`）；
- 可通过 **主进程 IPC** 封装 API，避免渲染进程暴露过多能力。

参见 `18-多客户端API Service架构方案.md` 中 **5.2 Electron 桌面客户端** 示例（`axios`、`WebSocket`、`ipcMain.handle`）。

---

## 2. 架构中的两条“连接”

### 2.1 控制面：REST

开机、关机、列表、查询状态等，路径为：

**Electron → API Gateway → API Service（novasphere-api）→ Kubernetes API → Wukong / KubeVirt 相关资源**

这是典型的**声明式管理 API**，不承载桌面像素或串口原始流。

### 2.2 数据面：控制台（图形 / 串口）

方案中约定通过 **WebSocket** 提供控制台能力，例如：

- `GET /api/v1/wukongs/:name/console`：获取控制台相关信息（如 URL、参数等，视具体实现而定）；
- `WebSocket /api/v1/wukongs/:name/console/ws`：**双向流**，用于键盘、鼠标、画面或串口数据的转发。

Electron 侧示例形态：

```text
wss://api.example.com/api/v1/wukongs/{name}/console/ws?token=...
```

API Gateway 必须正确代理 **WebSocket Upgrade**（超时、缓冲、不重试等见 `23-网关流式数据代理详解.md`）。

---

## 3. 原理：谁在真正对接 KubeVirt / 虚拟机

典型模式是 **API Service 作为桥（代理）**：

1. **Electron** 仅与集群外的 **HTTPS/WSS 端点**建立连接（经网关鉴权、TLS）。
2. **API Service** 在集群内使用 **client-go**、**KubeVirt 子资源**或等价能力（与 `virtctl console` / `vnc` 同类思路），连接到 **KubeVirt 为 VMI 暴露的 VNC / 串口**（由 KubeVirt 在 Pod 网络内提供，`13.11.1-VNC控制台.md` 中有 VMI `graphics` 等说明）。
3. 服务在 **VNC（或串口）二进制协议** 与 **WebSocket 帧** 之间做转发；也可能先转为前端 **noVNC** 等组件所需的帧格式，取决于实现选型。

因此：**图形/串口流量一般在集群内的 API 服务上终结，而不是用户电脑直连虚拟机 IP**。这样便于统一做 **认证、鉴权、审计、TLS 与网络隔离**。

`18-多客户端API Service架构方案.md` 中 **4.2 WebSocket** 伪代码表达了「从 KubeVirt 读写字节流 ↔ WebSocket 客户端」的意图。

---

## 4. 与「原生 VNC 客户端」路径的对比（可选）

另一种做法是下发 **带短期 Token 的 VNC URL** 或提供 **受控 TCP 隧道**，由 **TigerVNC** 等原生客户端直连。这是独立路径，需在**暴露面、防火墙、票据轮换**上单独设计。本文档所述主方案是 **统一走 API + WebSocket**，与多客户端（Web / Electron / Flutter）一致。

---

## 5. 文档与实现状态说明

- **架构与协议分工**：以 `17`～`23` 及 `18` 中多客户端方案为准。
- **控制台功能在业务上的落地上**：`13.11.1-VNC控制台.md` 等文档中部分能力可能仍为规划；讲解或面试时应区分 **设计原理** 与 **仓库当前实现范围**。

---

## 6. 一句话总结

Electron 通过 **HTTPS 管理虚拟机生命周期**，通过 **WSS 订阅控制台流**；与 KubeVirt 控制台子系统真正对接的是集群内的 **API（代理）服务**，从而在安全边界清晰的前提下完成远程桌面类访问。
