# Go 与 Kubernetes 依赖升级（面试要点）

面向本类 Operator 项目（client-go、controller-runtime、CRD/Admission），升级时面试官常问「怎么升、升坏了怎么办」。

## 1. Go 版本升级

- **动机**：安全修复、编译器与运行时优化、标准库能力（如 `log/slog`）、工具链对模块解析的改进。
- **注意点**：在 CI 中固定 `go` 版本；检查 `toolchain` 指令是否与团队策略一致；第三方库是否声明了最低 Go 版本。
- **可答话术**：「小版本跟进、大版本在独立分支跑全量测试；升级后优先看编译错误与 `staticcheck`/`govulncheck`。」

## 2. Kubernetes 依赖对齐

- **原则**：`k8s.io/api`、`k8s.io/apimachinery`、`k8s.io/client-go` 与**目标集群小版本**尽量同一代；controller-runtime 发布说明中会标明支持的 K8s 版本区间。
- **破坏性变更**：旧版 API 删除（如部分 `beta` API）、字段语义变化、Informer/Lister 行为差异。
- **实操**：读 [Kubernetes 弃用指南](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)，对 CRD 用 `controller-gen` 重新生成 manifests，在真实或 kind 集群上做兼容性测试。

## 3. 代码与清单层面检查清单

- **代码**：`context` 传递、错误包装（`fmt.Errorf("%w")`）、Reconcile 返回值与 `RequeueAfter` 语义是否仍符合新版 runtime。
- **清单**：CRD `apiVersion`、`conversion`/`subresources`、Webhook 配置与证书轮转（cert-manager 版本协同）。
- **面试加分**：提到用 **envtest** 或 **integration** 测试覆盖升级路径，而不仅依赖单元测试。

## 4. 与本项目相关的一句话

升级不仅是 bump 版本号，而是 **API 语义 + 运行时行为 + 集群侧 CRD/Webhook** 三联调；VM Operator 还受 **KubeVirt API** 版本约束，需与集群内 KubeVirt 一并规划。
