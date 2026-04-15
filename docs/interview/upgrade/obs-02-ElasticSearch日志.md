# Golang + Elasticsearch 日志（面试要点）

说明：生产里日志栈常见为 **EFK/ELK**（Fluent Bit/Fluentd/Filebeat → Kafka 可选 → ES → Kibana）或托管方案；面试重**模型、检索、成本**，不必绑定某一厂商。

## 1. 日志该记什么（结构化）

- **字段**：`timestamp`、`level`、`service`、`trace_id`（若对接 Tracing）、`namespace`、`pod`、`reconcile_id` 或 `wukong.name`（注意 PII 与体积）。
- **Go 实践**：统一用 `log/slog` 或 `zap` 等结构化输出；避免在热路径打印大对象。

## 2. Elasticsearch 核心概念（简答）

- **Index / ILM**：索引生命周期（热温冷、删除）控制成本与查询性能。
- **Mapping**：`keyword` vs `text`；聚合与精确匹配多用 `keyword`。
- **分片**：分片数影响写入与恢复时间；过小难扩展，过大浪费资源。

## 3. 查询与排障（面试）

- **KQL/Lucene 基础**：按 `level:ERROR`、时间范围、服务名过滤；会用 `bool` 查询组合条件即可。
- **慢查询**：大时间窗 + 高基数字段聚合 → 压力；可答「缩小范围、用 rollup/transform、或把明细放对象存储只索引摘要」。

## 4. 与 Kubernetes 集成

- **采集**：DaemonSet 采集容器 stdout（JSON 一行一条最佳）；或 sidecar（权衡资源）。
- **关联**：同一请求在 Access log、应用 log、Audit 里用 **request id** 对齐；Operator 可把 **reconcile key** 打进日志便于从告警跳日志。

## 5. 与 Prometheus 分工（必会对比）

- **Metrics**：趋势、告警、SLO。
- **Logs**：上下文、栈、单次失败原因。
- **话术**：「告警由指标触发，定位用日志与事件；避免用日志做本应指标承载的高频统计。」

## 6. 与本项目

Wukong 协调多子资源时，可举例：在 **Error 条件**变更时打一条结构化日志（含 `phase`、下游资源 GVK），便于在 ES 中按 `wukong` 名称串联全链路。
