# API Service 项目组织方案

## 1. 概述

API Service 架构方案的项目组织方式，有两种选择：**新建独立项目**或**在现有项目中添加**。

## 2. 方案对比

### 2.1 方案 A：新建独立项目（推荐）

```
novasphere/
├── vmoperator/              # Controller 项目
│   ├── api/
│   ├── internal/controller/
│   └── ...
└── novasphere-api/          # API Service 项目（新建）
    ├── cmd/
    │   └── api-server/
    ├── internal/
    │   ├── handlers/
    │   ├── services/
    │   └── middleware/
    ├── pkg/
    ├── Dockerfile
    └── go.mod
```

**优势**：
- ✅ 职责清晰，独立维护
- ✅ 独立版本控制
- ✅ 独立部署和扩展
- ✅ 团队可以并行开发
- ✅ 技术栈可以不同（如 Node.js）

**劣势**：
- ❌ 需要维护两个项目
- ❌ 代码可能重复

### 2.2 方案 B：在现有项目中添加（Monorepo）

```
vmoperator/
├── api/                     # CRD API（现有）
├── internal/
│   ├── controller/         # Controller（现有）
│   └── api/                # API Service（新增）
│       ├── server.go
│       ├── handlers/
│       └── middleware/
├── cmd/
│   ├── main.go            # Controller main（现有）
│   └── api-server/        # API Service main（新增）
│       └── main.go
├── Dockerfile              # Controller Dockerfile（现有）
├── Dockerfile.api         # API Service Dockerfile（新增）
└── go.mod
```

**优势**：
- ✅ 代码共享方便
- ✅ 统一版本管理
- ✅ 部署简单

**劣势**：
- ❌ 项目结构复杂
- ❌ 耦合度高
- ❌ 扩展性差

## 3. 推荐方案：新建独立项目

### 3.1 项目结构

```
novasphere-api/
├── cmd/
│   └── api-server/
│       └── main.go
├── internal/
│   ├── handlers/          # HTTP 处理器
│   │   ├── wukong.go
│   │   ├── vm.go
│   │   └── console.go
│   ├── services/          # 业务逻辑
│   │   ├── wukong_service.go
│   │   └── kubevirt_service.go
│   ├── middleware/        # 中间件
│   │   ├── auth.go
│   │   ├── logging.go
│   │   └── cors.go
│   └── client/            # Kubernetes 客户端
│       └── k8s_client.go
├── pkg/
│   ├── api/               # API 模型
│   │   └── models.go
│   └── utils/             # 工具函数
│       └── response.go
├── configs/
│   ├── config.yaml
│   └── k8s/
│       └── deployment.yaml
├── Dockerfile
├── go.mod
├── go.sum
└── README.md
```

### 3.2 项目初始化

```bash
# 1. 创建新项目
mkdir -p novasphere-api
cd novasphere-api

# 2. 初始化 Go 模块
go mod init github.com/kuihuar/novasphere-api

# 3. 创建目录结构
mkdir -p cmd/api-server
mkdir -p internal/{handlers,services,middleware,client}
mkdir -p pkg/{api,utils}
mkdir -p configs/k8s

# 4. 添加依赖
go get github.com/gin-gonic/gin
go get sigs.k8s.io/controller-runtime/pkg/client
go get k8s.io/client-go/kubernetes
```

### 3.3 代码示例

#### 3.3.1 main.go

```go
// cmd/api-server/main.go
package main

import (
    "context"
    "flag"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
    
    "github.com/gin-gonic/gin"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
    "sigs.k8s.io/controller-runtime/pkg/client"
    "sigs.k8s.io/controller-runtime/pkg/client/config"
    
    "github.com/kuihuar/novasphere-api/internal/handlers"
    "github.com/kuihuar/novasphere-api/internal/middleware"
    "github.com/kuihuar/novasphere-api/internal/services"
)

var (
    port = flag.String("port", "8080", "API server port")
    kubeconfig = flag.String("kubeconfig", "", "Path to kubeconfig file")
)

func main() {
    flag.Parse()
    
    // 初始化 Kubernetes 客户端
    k8sClient, k8sClientset, err := initK8sClient()
    if err != nil {
        panic(err)
    }
    
    // 初始化服务
    wukongService := services.NewWukongService(k8sClient)
    kubevirtService := services.NewKubevirtService(k8sClient, k8sClientset)
    
    // 初始化处理器
    wukongHandler := handlers.NewWukongHandler(wukongService)
    vmHandler := handlers.NewVMHandler(kubevirtService)
    consoleHandler := handlers.NewConsoleHandler(kubevirtService)
    
    // 创建 Gin 路由
    router := gin.Default()
    
    // 中间件
    router.Use(middleware.CORS())
    router.Use(middleware.Logging())
    router.Use(middleware.Auth())
    
    // API 路由
    api := router.Group("/api/v1")
    {
        // Wukong 管理
        api.GET("/wukongs", wukongHandler.List)
        api.POST("/wukongs", wukongHandler.Create)
        api.GET("/wukongs/:name", wukongHandler.Get)
        api.PUT("/wukongs/:name", wukongHandler.Update)
        api.DELETE("/wukongs/:name", wukongHandler.Delete)
        
        // VM 操作
        api.POST("/wukongs/:name/start", wukongHandler.Start)
        api.POST("/wukongs/:name/stop", wukongHandler.Stop)
        api.POST("/wukongs/:name/restart", wukongHandler.Restart)
        
        // 控制台
        api.GET("/wukongs/:name/console", consoleHandler.GetConsoleURL)
        api.GET("/wukongs/:name/console/ws", consoleHandler.WebSocket)
    }
    
    // 启动服务器
    srv := &http.Server{
        Addr:    ":" + *port,
        Handler: router,
    }
    
    // 优雅关闭
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            panic(err)
        }
    }()
    
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    if err := srv.Shutdown(ctx); err != nil {
        panic(err)
    }
}

func initK8sClient() (client.Client, *kubernetes.Clientset, error) {
    var cfg *rest.Config
    var err error
    
    if *kubeconfig != "" {
        cfg, err = clientcmd.BuildConfigFromFlags("", *kubeconfig)
    } else {
        cfg, err = config.GetConfig()
    }
    
    if err != nil {
        return nil, nil, err
    }
    
    k8sClient, err := client.New(cfg, client.Options{})
    if err != nil {
        return nil, nil, err
    }
    
    k8sClientset, err := kubernetes.NewForConfig(cfg)
    if err != nil {
        return nil, nil, err
    }
    
    return k8sClient, k8sClientset, nil
}
```

#### 3.3.2 Handler 示例

```go
// internal/handlers/wukong.go
package handlers

import (
    "net/http"
    
    "github.com/gin-gonic/gin"
    "github.com/kuihuar/novasphere-api/internal/services"
    "github.com/kuihuar/novasphere-api/pkg/api"
)

type WukongHandler struct {
    service *services.WukongService
}

func NewWukongHandler(service *services.WukongService) *WukongHandler {
    return &WukongHandler{service: service}
}

func (h *WukongHandler) List(c *gin.Context) {
    wukongs, err := h.service.List(c.Request.Context())
    if err != nil {
        api.ErrorResponse(c, http.StatusInternalServerError, err.Error())
        return
    }
    api.SuccessResponse(c, wukongs)
}

func (h *WukongHandler) Create(c *gin.Context) {
    var wukong vmv1alpha1.Wukong
    if err := c.ShouldBindJSON(&wukong); err != nil {
        api.ErrorResponse(c, http.StatusBadRequest, err.Error())
        return
    }
    
    if err := h.service.Create(c.Request.Context(), &wukong); err != nil {
        api.ErrorResponse(c, http.StatusInternalServerError, err.Error())
        return
    }
    
    api.SuccessResponse(c, wukong)
}

func (h *WukongHandler) Start(c *gin.Context) {
    name := c.Param("name")
    
    if err := h.service.Start(c.Request.Context(), name); err != nil {
        api.ErrorResponse(c, http.StatusInternalServerError, err.Error())
        return
    }
    
    api.SuccessResponse(c, gin.H{"message": "Wukong started"})
}
```

#### 3.3.3 Service 示例

```go
// internal/services/wukong_service.go
package services

import (
    "context"
    "fmt"
    
    "sigs.k8s.io/controller-runtime/pkg/client"
    vmv1alpha1 "github.com/kuihuar/vmoperator/api/v1alpha1"
)

type WukongService struct {
    k8sClient client.Client
}

func NewWukongService(k8sClient client.Client) *WukongService {
    return &WukongService{k8sClient: k8sClient}
}

func (s *WukongService) List(ctx context.Context) ([]vmv1alpha1.Wukong, error) {
    var wukongs vmv1alpha1.WukongList
    if err := s.k8sClient.List(ctx, &wukongs); err != nil {
        return nil, err
    }
    return wukongs.Items, nil
}

func (s *WukongService) Create(ctx context.Context, wukong *vmv1alpha1.Wukong) error {
    return s.k8sClient.Create(ctx, wukong)
}

func (s *WukongService) Start(ctx context.Context, name string) error {
    var wukong vmv1alpha1.Wukong
    if err := s.k8sClient.Get(ctx, client.ObjectKey{Name: name}, &wukong); err != nil {
        return err
    }
    
    if wukong.Spec.StartStrategy == nil {
        wukong.Spec.StartStrategy = &vmv1alpha1.StartStrategySpec{}
    }
    wukong.Spec.StartStrategy.AutoStart = true
    
    return s.k8sClient.Update(ctx, &wukong)
}
```

### 3.4 依赖管理

#### 3.4.1 go.mod

```go
module github.com/kuihuar/novasphere-api

go 1.21

require (
    github.com/gin-gonic/gin v1.9.1
    k8s.io/api v0.28.0
    k8s.io/apimachinery v0.28.0
    k8s.io/client-go v0.28.0
    sigs.k8s.io/controller-runtime v0.16.0
    github.com/kuihuar/vmoperator v0.1.0  // 引用 Controller 项目的 API
)

replace github.com/kuihuar/vmoperator => ../vmoperator
```

#### 3.4.2 共享代码

如果需要共享代码，可以：

1. **使用 Go 模块引用**：
```go
// 在 novasphere-api 中引用 vmoperator 的 API
import vmv1alpha1 "github.com/kuihuar/vmoperator/api/v1alpha1"
```

2. **发布共享包**：
```go
// 创建共享包项目
github.com/kuihuar/novasphere-sdk
```

## 4. Monorepo 方案（备选）

如果选择在现有项目中添加：

### 4.1 项目结构

```
vmoperator/
├── cmd/
│   ├── main.go           # Controller
│   └── api-server/       # API Service（新增）
│       └── main.go
├── internal/
│   ├── controller/       # Controller 逻辑
│   └── api/              # API Service 逻辑（新增）
│       ├── server.go
│       ├── handlers/
│       └── services/
├── Dockerfile             # Controller
├── Dockerfile.api        # API Service（新增）
└── Makefile              # 添加 API Service 构建命令
```

### 4.2 Makefile 更新

```makefile
# 构建 API Service
.PHONY: build-api
build-api: ## Build API Service
	go build -o bin/api-server ./cmd/api-server

# 构建 API Service 镜像
.PHONY: docker-build-api
docker-build-api: ## Build API Service docker image
	docker build -f Dockerfile.api -t ${IMG_API} .

# 部署 API Service
.PHONY: deploy-api
deploy-api: kustomize ## Deploy API Service
	cd config/api && "$(KUSTOMIZE)" edit set image api-server=${IMG_API}
	"$(KUSTOMIZE)" build config/api | "$(KUBECTL)" apply -f -
```

## 5. 推荐方案总结

### 5.1 新建独立项目（推荐）

**适用场景**：
- ✅ 团队规模较大
- ✅ 需要独立部署和扩展
- ✅ API Service 可能使用不同技术栈
- ✅ 需要独立的版本控制

**项目结构**：
```
novasphere/
├── vmoperator/          # Controller 项目
└── novasphere-api/      # API Service 项目（新建）
```

### 5.2 Monorepo 方案

**适用场景**：
- ✅ 小团队
- ✅ 代码共享需求高
- ✅ 统一部署
- ✅ 简单维护

**项目结构**：
```
vmoperator/              # 包含 Controller 和 API Service
├── cmd/
│   ├── main.go         # Controller
│   └── api-server/     # API Service
```

## 6. 实施建议

### 6.1 第一阶段：Monorepo（快速验证）

1. 在现有项目中添加 API Service 代码
2. 快速验证功能
3. 测试多客户端支持

### 6.2 第二阶段：独立项目（生产环境）

1. 创建独立的 `novasphere-api` 项目
2. 迁移代码
3. 独立部署和扩展

## 7. 总结

- **推荐**：新建独立项目 `novasphere-api`
- **备选**：在现有项目中添加（Monorepo）
- **选择依据**：团队规模、维护需求、技术栈

