# Controller-Runtime 与 Operator 生态演进（面试要点）

## 1. controller-runtime 核心（巩固）

- **Manager**：缓存、Client、Scheme、Webhook、Metrics、Leader Election 的统一入口。
- **Reconcile**：幂等、只依赖当前对象与集群观测状态；避免在 Reconcile 里做长阻塞 IO。
- **Watches 与 Owns**：正确声明 `Owns`/`Watches`，减少漏调和多余全表扫描。

## 2. 升级后可强化的能力

- **Metrics**：向 Prometheus 暴露 workqueue 深度、Reconcile 耗时直方图、错误计数；与 Grafana 仪表盘结合讲「如何发现协调风暴」。
- **Health / Ready**：`healthz`/`readyz` 与 Leader 身份结合，说明滚动升级时如何避免双主或误杀。
- **优雅关闭**：context 取消时 Informer 停止顺序，避免升级 Pod 时短暂不一致。

## 3. 新框架与工具（面试可提「可选演进」）

- **Operator SDK / Kubebuilder**：脚手架、API 版本迭代、bundle 与 OLM（若走向 OperatorHub）。
- **ValidatingAdmissionPolicy（VAP）**：部分校验从 Webhook 迁到内置策略（视集群版本与团队选型）。
- **Gateway API**：若未来 Ingress 形态统一，可与 Service 暴露方案（见主文档网络章节）对照讨论。

## 4. 设计题常见问法

- 「如何避免两个 Controller 同时改同一资源？」→ OwnerReference、Finalizer、字段级 patch、或单一协调者模式。
- 「如何调试 Reconcile 不触发？」→ 事件源、Resync、索引、以及 `Predicate` 是否过滤过度。

## 5. 与本项目

Wukong 协调网络、存储、KubeVirt 多条子路径时，可强调：**分阶段 status、条件（Conditions）建模、以及可观测性指标** 是升级后保持可运维性的关键。
