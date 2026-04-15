# 升级与可观测性（面试补充）

本目录与主文档 `docs/interview/00-README.md` 配合使用，聚焦：**项目若持续升级可引入的新知识/新框架**，以及 **Golang 可观测性**（监控 Prometheus、日志 Elasticsearch、研发侧经验）。

## 阅读顺序建议

1. 先读与当前栈最相关的升级短文（Go / K8s / controller-runtime）。
2. 再按需读虚拟化与集群周边方向（与 k3s、KubeVirt、Multus、Longhorn 等对齐）。
3. 可观测性按「指标 → 日志 → 落地经验」顺序阅读。

## 文档列表

### 技术栈升级方向

| 文件 | 内容概要 |
|------|----------|
| [01-Go与Kubernetes依赖升级.md](./01-Go与Kubernetes依赖升级.md) | Go 版本、K8s client-go/apimachinery 对齐、弃用 API、测试与构建 |
| [02-Controller-Runtime与Operator生态演进.md](./02-Controller-Runtime与Operator生态演进.md) | controller-runtime、Kubebuilder、准入与扩展、可观测性挂钩 |
| [03-虚拟化与集群组件升级关注点.md](./03-虚拟化与集群组件升级关注点.md) | KubeVirt、CDI、CNI、存储与发行版升级时的耦合与验证 |

### Golang 可观测性（面试）

| 文件 | 内容概要 |
|------|----------|
| [obs-01-Prometheus监控.md](./obs-01-Prometheus监控.md) | 指标模型、Operator 侧实践、Prometheus Operator、常见面试题 |
| [obs-02-ElasticSearch日志.md](./obs-02-ElasticSearch日志.md) | 日志链路、索引与检索、与 K8s 集成、面试要点 |
| [obs-03-可观测性研发经验.md](./obs-03-可观测性研发经验.md) | SLO/告警、排障思路、成本与规范 |

### 后续扩展（分类路线图，可按篇拆文）

| 文件 | 内容概要 |
|------|----------|
| [04-后续扩展主题分类.md](./04-后续扩展主题分类.md) | 下一批可写主题按类整理：OTel/Tracing、指标长期存储、日志管道、网关观测、安全合规、升级演练与测试、平台化等 |

## 与主项目的对应关系

VM Operator 当前技术主线见 `01-整体架构概览.md`：声明式 CRD、controller-runtime Reconcile、k3s + KubeVirt + 多网与存储。升级文档不替代主文档，仅补充**升级决策**与**可观测性面试**话术与知识点。
