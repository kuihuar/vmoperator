# API Service 框架选择方案

## 1. 概述

API Service 可以使用多种框架实现，本文档对比不同方案。

## 2. 框架对比

### 2.1 HTTP 框架对比

| 框架 | 语言 | 性能 | 易用性 | 生态 | 推荐度 |
|------|------|------|--------|------|--------|
| **Gin** | Go | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Echo** | Go | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Fiber** | Go | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Chi** | Go | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Express** | Node.js | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **FastAPI** | Python | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |

### 2.2 gRPC 框架

| 框架 | 语言 | 性能 | 易用性 | 推荐度 |
|------|------|------|--------|--------|
| **gRPC-Go** | Go | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **grpc-node** | Node.js | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

## 3. 方案一：Gin（推荐）

### 3.1 优势

- ✅ 性能好
- ✅ 文档完善
- ✅ 中间件丰富
- ✅ 社区活跃
- ✅ 与 Kubernetes 生态兼容好
- ✅ **原生支持流式响应**（SSE、流式 JSON，无需额外库）

### 3.2 实现示例

```go
// cmd/api-server/main.go
package main

import (
    "github.com/gin-gonic/gin"
    "github.com/kuihuar/novasphere-api/internal/handlers"
    "github.com/kuihuar/novasphere-api/internal/middleware"
)

func main() {
    router := gin.Default()
    
    // 中间件
    router.Use(middleware.CORS())
    router.Use(middleware.Auth())
    router.Use(middleware.Logging())
    
    // 路由
    api := router.Group("/api/v1")
    {
        api.GET("/wukongs", handlers.ListWukongs)
        api.POST("/wukongs", handlers.CreateWukong)
    }
    
    router.Run(":8080")
}
```

### 3.3 流式响应支持

Gin **原生支持流式响应**，使用标准库的 `http.Flusher` 接口：

```go
func StreamWukongStatus(c *gin.Context) {
    c.Header("Content-Type", "text/event-stream")
    
    w := c.Writer
    flusher, _ := w.(http.Flusher)
    
    for {
        data := getData()
        fmt.Fprintf(w, "data: %s\n\n", data)
        flusher.Flush() // 立即刷新，实现流式传输
    }
}
```

**注意**：WebSocket 需要额外库（`gorilla/websocket`），但 SSE 和流式 JSON **不需要**。

### 3.4 适用场景

- ✅ 标准 RESTful API
- ✅ Web 和 Electron 客户端
- ✅ 需要丰富的中间件
- ✅ **流式数据传输**（SSE、流式 JSON）
- ✅ 快速开发

## 4. 方案二：Echo

### 4.1 优势

- ✅ 性能更好（比 Gin 快）
- ✅ 更轻量
- ✅ 内置更多功能
- ✅ 更好的错误处理

### 4.2 实现示例

```go
// cmd/api-server/main.go
package main

import (
    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"
    "github.com/kuihuar/novasphere-api/internal/handlers"
)

func main() {
    e := echo.New()
    
    // 中间件
    e.Use(middleware.CORS())
    e.Use(middleware.Logger())
    e.Use(middleware.Recover())
    
    // 路由
    api := e.Group("/api/v1")
    {
        api.GET("/wukongs", handlers.ListWukongs)
        api.POST("/wukongs", handlers.CreateWukong)
    }
    
    e.Logger.Fatal(e.Start(":8080"))
}
```

### 4.3 适用场景

- ✅ 高性能要求
- ✅ 需要更好的错误处理
- ✅ 轻量级需求

## 5. 方案三：Fiber

### 5.1 优势

- ✅ 性能极高（基于 FastHTTP）
- ✅ Express 风格的 API
- ✅ 内置 WebSocket 支持
- ✅ **支持流式响应**（Server-Sent Events、流式数据）
- ✅ 内存占用低

### 5.2 实现示例

```go
// cmd/api-server/main.go
package main

import (
    "github.com/gofiber/fiber/v2"
    "github.com/gofiber/fiber/v2/middleware/cors"
    "github.com/gofiber/fiber/v2/middleware/logger"
    "github.com/kuihuar/novasphere-api/internal/handlers"
)

func main() {
    app := fiber.New()
    
    // 中间件
    app.Use(cors.New())
    app.Use(logger.New())
    
    // 路由
    api := app.Group("/api/v1")
    {
        api.Get("/wukongs", handlers.ListWukongs)
        api.Post("/wukongs", handlers.CreateWukong)
        api.Get("/wukongs/:name/stream", handlers.StreamWukongStatus) // 流式接口
    }
    
    app.Listen(":8080")
}
```

### 5.3 流式响应支持

Fiber **支持流式返回数据**，可以通过以下方式实现：

#### 5.3.1 Server-Sent Events (SSE)

```go
// internal/handlers/stream.go
package handlers

import (
    "fmt"
    "time"
    
    "github.com/gofiber/fiber/v2"
)

func StreamWukongStatus(c *fiber.Ctx) error {
    wukongName := c.Params("name")
    
    // 设置 SSE 响应头
    c.Set("Content-Type", "text/event-stream")
    c.Set("Cache-Control", "no-cache")
    c.Set("Connection", "keep-alive")
    c.Set("X-Accel-Buffering", "no") // 禁用 Nginx 缓冲
    
    // 流式发送数据
    return c.Context().SetBodyStreamWriter(func(w *bufio.Writer) {
        ticker := time.NewTicker(1 * time.Second)
        defer ticker.Stop()
        
        for {
            select {
            case <-ticker.C:
                // 获取 Wukong 状态
                status := getWukongStatus(wukongName)
                
                // 发送 SSE 格式数据
                fmt.Fprintf(w, "data: %s\n\n", status)
                w.Flush()
                
            case <-c.Context().Done():
                return
            }
        }
    })
}
```

#### 5.3.2 流式 JSON 响应

```go
func StreamWukongList(c *fiber.Ctx) error {
    c.Set("Content-Type", "application/json")
    
    return c.Context().SetBodyStreamWriter(func(w *bufio.Writer) {
        w.WriteString("[")
        
        wukongs := getWukongs()
        for i, wukong := range wukongs {
            if i > 0 {
                w.WriteString(",")
            }
            
            json, _ := json.Marshal(wukong)
            w.Write(json)
            w.Flush()
            
            time.Sleep(100 * time.Millisecond) // 模拟流式传输
        }
        
        w.WriteString("]")
        w.Flush()
    })
}
```

#### 5.3.3 WebSocket 流式数据

```go
import (
    "github.com/gofiber/websocket/v2"
)

func SetupWebSocket(app *fiber.App) {
    app.Get("/ws", websocket.New(func(c *websocket.Conn) {
        for {
            // 读取客户端消息
            _, msg, err := c.ReadMessage()
            if err != nil {
                break
            }
            
            // 处理消息并流式返回
            response := processMessage(msg)
            
            // 发送响应
            if err := c.WriteMessage(websocket.TextMessage, response); err != nil {
                break
            }
        }
    }))
}
```

### 5.4 适用场景

- ✅ 极致性能要求
- ✅ 高并发场景
- ✅ 需要 WebSocket 支持
- ✅ **需要流式数据传输**（SSE、流式 JSON）
- ✅ 资源受限环境

## 6. 方案四：gRPC（高性能场景）

### 6.1 是否需要 gRPC？

**需要 gRPC 的场景**：
- ✅ 高性能要求（内部服务调用）
- ✅ 流式数据传输
- ✅ 多语言客户端
- ✅ 强类型接口

**不需要 gRPC 的场景**：
- ❌ Web 前端（浏览器不支持）
- ❌ 简单 RESTful API
- ❌ 快速开发

### 6.2 gRPC 实现

#### 6.2.1 定义 Proto

```protobuf
// api/proto/wukong.proto
syntax = "proto3";

package novasphere.v1;

option go_package = "github.com/kuihuar/novasphere-api/api/proto";

service WukongService {
    rpc ListWukongs(ListWukongsRequest) returns (ListWukongsResponse);
    rpc GetWukong(GetWukongRequest) returns (GetWukongResponse);
    rpc CreateWukong(CreateWukongRequest) returns (CreateWukongResponse);
    rpc UpdateWukong(UpdateWukongRequest) returns (UpdateWukongResponse);
    rpc DeleteWukong(DeleteWukongRequest) returns (DeleteWukongResponse);
    
    rpc StartWukong(StartWukongRequest) returns (StartWukongResponse);
    rpc StopWukong(StopWukongRequest) returns (StopWukongResponse);
    
    // 流式接口（实时状态更新）
    rpc WatchWukong(WatchWukongRequest) returns (stream WukongEvent);
}

message ListWukongsRequest {
    string namespace = 1;
    map<string, string> labels = 2;
}

message ListWukongsResponse {
    repeated Wukong wukongs = 1;
}

message Wukong {
    string name = 1;
    string namespace = 2;
    WukongSpec spec = 3;
    WukongStatus status = 4;
}

message WukongSpec {
    int32 cpu = 1;
    string memory = 2;
    repeated Disk disks = 3;
    repeated Network networks = 4;
}

message WukongStatus {
    string phase = 1;
    string vm_name = 2;
    repeated Condition conditions = 3;
}
```

#### 6.2.2 实现 gRPC 服务

```go
// internal/grpc/wukong_server.go
package grpc

import (
    "context"
    
    "google.golang.org/grpc"
    "github.com/kuihuar/novasphere-api/api/proto"
    "github.com/kuihuar/novasphere-api/internal/services"
)

type WukongServer struct {
    proto.UnimplementedWukongServiceServer
    service *services.WukongService
}

func NewWukongServer(service *services.WukongService) *WukongServer {
    return &WukongServer{service: service}
}

func (s *WukongServer) ListWukongs(ctx context.Context, req *proto.ListWukongsRequest) (*proto.ListWukongsResponse, error) {
    wukongs, err := s.service.List(ctx)
    if err != nil {
        return nil, err
    }
    
    // 转换为 proto 格式
    protoWukongs := make([]*proto.Wukong, 0, len(wukongs))
    for _, w := range wukongs {
        protoWukongs = append(protoWukongs, convertToProto(w))
    }
    
    return &proto.ListWukongsResponse{Wukongs: protoWukongs}, nil
}

func (s *WukongServer) WatchWukong(req *proto.WatchWukongRequest, stream proto.WukongService_WatchWukongServer) error {
    // 流式推送 Wukong 状态更新
    events := s.service.Watch(context.Background(), req.Name)
    
    for event := range events {
        if err := stream.Send(convertEventToProto(event)); err != nil {
            return err
        }
    }
    
    return nil
}
```

#### 6.2.3 启动 gRPC 服务器

```go
// cmd/api-server/main.go
package main

import (
    "net"
    
    "google.golang.org/grpc"
    "github.com/kuihuar/novasphere-api/api/proto"
    "github.com/kuihuar/novasphere-api/internal/grpc"
)

func main() {
    // 创建 gRPC 服务器
    s := grpc.NewServer()
    
    // 注册服务
    wukongServer := grpc.NewWukongServer(wukongService)
    proto.RegisterWukongServiceServer(s, wukongServer)
    
    // 启动服务器
    lis, err := net.Listen("tcp", ":9090")
    if err != nil {
        panic(err)
    }
    
    if err := s.Serve(lis); err != nil {
        panic(err)
    }
}
```

## 7. 混合方案：RESTful + gRPC

### 7.1 架构

```
前端 (Web/Electron/Flutter)
    ↓ HTTP/RESTful
API Gateway
    ↓
API Service
    ├── HTTP Server (Gin/Echo) - 8080
    └── gRPC Server - 9090
        ↓
    Controller
```

### 7.2 实现

```go
// cmd/api-server/main.go
package main

import (
    "net"
    
    "github.com/gin-gonic/gin"
    "google.golang.org/grpc"
    "github.com/kuihuar/novasphere-api/internal/handlers"
    "github.com/kuihuar/novasphere-api/internal/grpc"
)

func main() {
    // 启动 HTTP 服务器（RESTful API）
    go startHTTPServer()
    
    // 启动 gRPC 服务器（内部服务调用）
    startGRPCServer()
}

func startHTTPServer() {
    router := gin.Default()
    
    api := router.Group("/api/v1")
    {
        api.GET("/wukongs", handlers.ListWukongs)
        api.POST("/wukongs", handlers.CreateWukong)
    }
    
    router.Run(":8080")
}

func startGRPCServer() {
    s := grpc.NewServer()
    proto.RegisterWukongServiceServer(s, grpcServer)
    
    lis, _ := net.Listen("tcp", ":9090")
    s.Serve(lis)
}
```

### 7.3 使用场景

- **HTTP/RESTful**：前端客户端（Web、Electron、Flutter）
- **gRPC**：内部服务调用、高性能场景、流式数据

## 8. 方案对比总结

### 8.1 HTTP 框架选择

| 场景 | 推荐框架 |
|------|---------|
| **标准 RESTful API** | Gin（推荐） |
| **高性能要求** | Fiber 或 Echo |
| **轻量级** | Echo |
| **WebSocket 支持** | Fiber |
| **流式数据传输** | Fiber（SSE、流式 JSON）或 gRPC |

### 8.2 流式数据支持对比

| 框架 | SSE | 流式 JSON | WebSocket | 需要额外库 |
|------|-----|----------|-----------|-----------|
| **Gin** | ✅ 原生支持 | ✅ 原生支持 | ✅ (gorilla/websocket) | WebSocket 需要 |
| **Echo** | ✅ 原生支持 | ✅ 原生支持 | ✅ (需要额外库) | WebSocket 需要 |
| **Fiber** | ✅ 原生支持 | ✅ 原生支持 | ✅ 内置 | 不需要 |
| **gRPC** | ❌ | ❌ | ❌ | ✅ gRPC Stream |

**说明**：
- **Gin/Echo**：SSE 和流式 JSON 都**原生支持**（使用 `http.Flusher`），**不需要额外库**
- **WebSocket**：Gin/Echo 需要额外库（如 `gorilla/websocket`），Fiber 内置支持

### 8.3 流式数据使用场景

**SSE (Server-Sent Events)**：
- ✅ 实时状态更新
- ✅ 日志流式输出
- ✅ 进度通知
- ✅ 浏览器原生支持

**WebSocket**：
- ✅ 双向通信
- ✅ 控制台交互
- ✅ 实时聊天
- ✅ 需要客户端交互

**gRPC Stream**：
- ✅ 内部服务调用
- ✅ 高性能流式传输
- ✅ 多语言支持
- ❌ 浏览器不支持（需要 gRPC-Web）

### 8.2 gRPC 使用建议

**需要 gRPC**：
- ✅ 内部服务间通信
- ✅ 高性能要求
- ✅ 流式数据传输
- ✅ 多语言客户端（非浏览器）

**不需要 gRPC**：
- ❌ Web 前端（浏览器不支持，需要 gRPC-Web）
- ❌ 简单 CRUD 操作
- ❌ 快速开发

### 8.3 推荐方案

**方案 A：Gin + gRPC（推荐）**

```
HTTP (Gin) - 8080    → 前端客户端
gRPC - 9090          → 内部服务调用
```

**方案 B：仅 Gin（简单）**

```
HTTP (Gin) - 8080    → 所有客户端
```

**方案 C：Fiber（极致性能）**

```
HTTP (Fiber) - 8080  → 所有客户端
WebSocket            → 实时通信
```

## 9. 实施建议

### 9.1 第一阶段：Gin（快速开发）

```go
// 使用 Gin 快速实现 RESTful API
router := gin.Default()
api := router.Group("/api/v1")
// ... 路由配置
```

### 9.2 第二阶段：添加 gRPC（如需要）

```go
// 添加 gRPC 服务器用于内部调用
grpcServer := grpc.NewServer()
// ... 注册服务
```

### 9.3 第三阶段：优化（如需要）

```go
// 如果性能成为瓶颈，考虑迁移到 Fiber
app := fiber.New()
// ... 路由配置
```

## 10. 代码示例对比

### 10.1 Gin vs Echo vs Fiber

```go
// Gin
router := gin.Default()
router.GET("/wukongs", handlers.ListWukongs)

// Echo
e := echo.New()
e.GET("/wukongs", handlers.ListWukongs)

// Fiber
app := fiber.New()
app.Get("/wukongs", handlers.ListWukongs)
```

### 10.2 性能测试

```bash
# 基准测试
go test -bench=. -benchmem

# 结果（仅供参考）
# Gin:     ~50k req/s
# Echo:    ~60k req/s
# Fiber:   ~100k req/s
```

## 11. 总结

### 11.1 推荐方案

**大多数场景**：**Gin**（平衡性能和易用性）

**高性能场景**：**Fiber** 或 **Echo**

**内部服务调用**：**gRPC**（可选）

### 11.2 选择依据

- **团队熟悉度**：选择团队熟悉的框架
- **性能要求**：根据实际需求选择
- **功能需求**：WebSocket、流式数据等
- **维护成本**：考虑长期维护

