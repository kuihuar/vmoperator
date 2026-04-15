# Golang + Prometheus 监控（面试要点）

## 1. 指标类型（必会）

- **Counter**：只增，如请求总数、Reconcile 次数。
- **Gauge**：可增可减，如队列深度、当前协程数、缓存大小。
- **Histogram / Summary**：延迟分布；Prometheus 侧常用 Histogram + `histogram_quantile` 算分位数。

## 2. Operator / Controller 常见指标

- **workqueue**：`depth`、`adds`、`retries`、`work_duration`（若使用标准 metrics）。
- **Reconcile**：`reconcile_total{result="success|error"}`、`reconcile_duration_seconds`。
- **业务域**：如「Wukong 处于 Error 的对象数」「长时间 Pending 的 VM 数」（需控制 label 基数）。

## 3. 高基数与 label 规范（高频考点）

- **避免**将用户自定义 name、UUID、Pod IP 等作为常规 metric label。
- **允许**的 label：`controller`、`verb`、`error_type`（枚举）、`phase`（有限状态）。
- **话术**：「指标用于趋势与告警，明细排查交给日志/Tracing。」

## 4. Kubernetes 侧集成

- **Prometheus Operator**：`ServiceMonitor`/`PodMonitor` 抓取注解或选器匹配。
- **kube-prometheus-stack**：集群组件与自定义应用统一采集；RBAC、TLS、远程写入（如 Thanos/Mimir）可一笔带过。

## 5. Go 客户端与暴露

- **prometheus/client_golang**：`promhttp` 注册 `/metrics`；与 `controller-runtime` 内置 registry 合并时注意重复注册问题。
- **面试延伸**：提到 **OpenTelemetry Metrics** 作为长期统一信号（与下文日志、Tracing 同源）的演进方向即可，不必展开实现细节。

## 6. 告警与 SLO（简答）

- **RED**：Rate、Errors、Duration，适合 HTTP/gRPC 服务。
- **USE**：Utilization、Saturation、Errors，适合节点与队列类资源。
- Operator 可举例：「Reconcile error rate 持续升高 + workqueue depth 不降 → 先查 API Server 限流或下游 CRD 冲突。」

## 7. 与本项目

VM Operator 可强调：在协调 KubeVirt、Multus、PVC 等多对象时，**分阶段 metrics**（网络子步骤耗时、存储绑定失败计数）比单一「总耗时」更易定位瓶颈。
