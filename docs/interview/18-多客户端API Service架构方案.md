# 多客户端 API Service 架构方案

## 1. 概述

当需要支持多个客户端（Web、Electron 桌面、Flutter 移动端）时，开发独立的 API Service 是最佳选择。

## 2. 为什么需要独立的 API Service

### 2.1 多客户端需求

- ✅ **Web 前端**：React/Vue，浏览器访问
- ✅ **Electron 桌面**：跨平台桌面应用
- ✅ **Flutter 移动端**：iOS/Android 原生应用

### 2.2 统一 API 的优势

- ✅ 一套 API 服务所有客户端
- ✅ 统一的认证授权
- ✅ 统一的业务逻辑
- ✅ 易于维护和扩展
- ✅ 支持不同协议（HTTP、WebSocket、gRPC）

## 3. 架构设计

### 3.1 整体架构

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Web 前端       │  │  Electron 桌面  │  │  Flutter 移动端 │
│  (React/Vue)    │  │  (Electron)     │  │  (Flutter)      │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   API Gateway     │
                    │  (Kong/Traefik)   │
                    │  - 认证授权        │
                    │  - 限流监控        │
                    │  - SSL 终止        │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  novasphere-api   │
                    │  (独立服务)       │
                    │  - RESTful API    │
                    │  - WebSocket      │
                    │  - gRPC (可选)    │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Controller       │
                    │  (Kubebuilder)    │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Kubernetes API   │
                    └──────────────────┘
```

### 3.2 API Service 设计

```go
// cmd/api-server/main.go
package main

import (
    "context"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
    
    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
    "google.golang.org/grpc"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

type APIServer struct {
    httpServer   *gin.Engine
    wsUpgrader   websocket.Upgrader
    grpcServer   *grpc.Server
    k8sClient    client.Client
}

func NewAPIServer(k8sClient client.Client) *APIServer {
    // HTTP Server (RESTful API)
    router := gin.Default()
    
    // CORS 配置（支持多客户端）
    router.Use(corsMiddleware())
    
    // 认证中间件
    router.Use(authMiddleware())
    
    // API 路由
    api := router.Group("/api/v1")
    {
        // Wukong 管理
        api.GET("/wukongs", listWukongs)
        api.POST("/wukongs", createWukong)
        api.GET("/wukongs/:name", getWukong)
        api.PUT("/wukongs/:name", updateWukong)
        api.DELETE("/wukongs/:name", deleteWukong)
        
        // VM 操作
        api.POST("/wukongs/:name/start", startWukong)
        api.POST("/wukongs/:name/stop", stopWukong)
        api.POST("/wukongs/:name/restart", restartWukong)
        api.POST("/wukongs/:name/suspend", suspendWukong)
        api.POST("/wukongs/:name/resume", resumeWukong)
        
        // 控制台
        api.GET("/wukongs/:name/console", getConsoleURL)
        api.WebSocket("/wukongs/:name/console/ws", consoleWebSocket)
        
        // 监控和统计
        api.GET("/wukongs/:name/metrics", getWukongMetrics)
        api.GET("/stats", getStats)
    }
    
    // WebSocket 升级器
    upgrader := websocket.Upgrader{
        CheckOrigin: func(r *http.Request) bool {
            return true // 生产环境需要检查 Origin
        },
    }
    
    return &APIServer{
        httpServer: router,
        wsUpgrader: upgrader,
        k8sClient:  k8sClient,
    }
}

func (s *APIServer) Start() error {
    // 启动 HTTP 服务器
    httpServer := &http.Server{
        Addr:    ":8080",
        Handler: s.httpServer,
    }
    
    // 启动 gRPC 服务器（可选）
    go s.startGRPCServer()
    
    // 优雅关闭
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    
    go func() {
        <-quit
        ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
        defer cancel()
        
        httpServer.Shutdown(ctx)
        s.grpcServer.GracefulStop()
    }()
    
    return httpServer.ListenAndServe()
}
```

## 4. 多协议支持

### 4.1 RESTful API（所有客户端）

```go
// 统一的 RESTful API
// GET /api/v1/wukongs
func listWukongs(c *gin.Context) {
    var wukongs vmv1alpha1.WukongList
    if err := k8sClient.List(ctx, &wukongs); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    
    // 统一响应格式
    c.JSON(http.StatusOK, gin.H{
        "code": 0,
        "message": "success",
        "data": wukongs.Items,
    })
}

// POST /api/v1/wukongs
func createWukong(c *gin.Context) {
    var wukong vmv1alpha1.Wukong
    if err := c.ShouldBindJSON(&wukong); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{
            "code": 400,
            "message": err.Error(),
        })
        return
    }
    
    if err := k8sClient.Create(ctx, &wukong); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{
            "code": 500,
            "message": err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusCreated, gin.H{
        "code": 0,
        "message": "success",
        "data": wukong,
    })
}
```

### 4.2 WebSocket（实时通信）

```go
// WebSocket 支持（控制台、实时状态更新）
func consoleWebSocket(c *gin.Context) {
    name := c.Param("name")
    
    // 升级到 WebSocket
    conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        return
    }
    defer conn.Close()
    
    // 处理控制台连接
    handleConsoleConnection(conn, name)
}

func handleConsoleConnection(conn *websocket.Conn, wukongName string) {
    // 连接到 KubeVirt VNC/Serial Console
    // 转发数据流
    for {
        // 从 KubeVirt 读取数据
        data := readFromKubeVirtConsole(wukongName)
        
        // 发送到客户端
        if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
            break
        }
        
        // 从客户端读取数据
        _, message, err := conn.ReadMessage()
        if err != nil {
            break
        }
        
        // 发送到 KubeVirt
        writeToKubeVirtConsole(wukongName, message)
    }
}
```

### 4.3 gRPC（高性能，可选）

```protobuf
// api/proto/wukong.proto
syntax = "proto3";

package novasphere.v1;

service WukongService {
    rpc ListWukongs(ListWukongsRequest) returns (ListWukongsResponse);
    rpc GetWukong(GetWukongRequest) returns (GetWukongResponse);
    rpc CreateWukong(CreateWukongRequest) returns (CreateWukongResponse);
    rpc UpdateWukong(UpdateWukongRequest) returns (UpdateWukongResponse);
    rpc DeleteWukong(DeleteWukongRequest) returns (DeleteWukongResponse);
    
    rpc StartWukong(StartWukongRequest) returns (StartWukongResponse);
    rpc StopWukong(StopWukongRequest) returns (StopWukongResponse);
    
    // 流式接口（实时状态）
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
```

## 5. 客户端适配

### 5.1 Web 前端（React/Vue）

```typescript
// web/src/api/client.ts
import axios from 'axios';

const apiClient = axios.create({
  baseURL: 'https://api.novasphere.io/api/v1',
  headers: {
    'Content-Type': 'application/json',
  },
});

// 认证拦截器
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// WebSocket 连接
export const createWebSocket = (wukongName: string) => {
  const token = localStorage.getItem('token');
  return new WebSocket(
    `wss://api.novasphere.io/api/v1/wukongs/${wukongName}/console/ws?token=${token}`
  );
};

export const wukongAPI = {
  list: () => apiClient.get('/wukongs'),
  get: (name: string) => apiClient.get(`/wukongs/${name}`),
  create: (wukong: any) => apiClient.post('/wukongs', wukong),
  start: (name: string) => apiClient.post(`/wukongs/${name}/start`),
  stop: (name: string) => apiClient.post(`/wukongs/${name}/stop`),
};
```

### 5.2 Electron 桌面客户端

```typescript
// electron/src/api/client.ts
import axios from 'axios';
import { app } from 'electron';

const apiClient = axios.create({
  baseURL: process.env.API_URL || 'https://api.novasphere.io/api/v1',
  headers: {
    'Content-Type': 'application/json',
    'X-Client-Type': 'electron',
    'X-Client-Version': app.getVersion(),
  },
});

// 从本地存储读取 token
apiClient.interceptors.request.use((config) => {
  const token = getStoredToken(); // Electron 的 secure storage
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// WebSocket 支持
import WebSocket from 'ws';

export const createWebSocket = (wukongName: string) => {
  const token = getStoredToken();
  return new WebSocket(
    `wss://api.novasphere.io/api/v1/wukongs/${wukongName}/console/ws?token=${token}`
  );
};

// 使用 IPC 通信
import { ipcMain } from 'electron';

ipcMain.handle('wukong:list', async () => {
  const response = await apiClient.get('/wukongs');
  return response.data;
});

ipcMain.handle('wukong:start', async (event, name: string) => {
  const response = await apiClient.post(`/wukongs/${name}/start`);
  return response.data;
});
```

### 5.3 Flutter 移动端

```dart
// flutter/lib/api/client.dart
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class APIClient {
  late Dio _dio;
  
  APIClient() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.novasphere.io/api/v1',
      headers: {
        'Content-Type': 'application/json',
        'X-Client-Type': 'flutter',
      },
    ));
    
    // 添加认证拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }
  
  // RESTful API
  Future<List<Wukong>> listWukongs() async {
    final response = await _dio.get('/wukongs');
    return (response.data['data'] as List)
        .map((json) => Wukong.fromJson(json))
        .toList();
  }
  
  Future<Wukong> createWukong(Wukong wukong) async {
    final response = await _dio.post('/wukongs', data: wukong.toJson());
    return Wukong.fromJson(response.data['data']);
  }
  
  Future<void> startWukong(String name) async {
    await _dio.post('/wukongs/$name/start');
  }
  
  // WebSocket 支持
  WebSocketChannel createConsoleWebSocket(String wukongName) {
    final prefs = SharedPreferences.getInstance();
    final token = prefs.then((p) => p.getString('token') ?? '');
    
    return WebSocketChannel.connect(
      Uri.parse('wss://api.novasphere.io/api/v1/wukongs/$wukongName/console/ws?token=$token'),
    );
  }
}
```

## 6. 认证授权

### 6.1 统一认证方案

```go
// 支持多种认证方式
func authMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // 1. JWT Token（所有客户端）
        token := c.GetHeader("Authorization")
        if token != "" {
            if claims, err := validateJWT(token); err == nil {
                c.Set("user", claims.User)
                c.Set("client_type", claims.ClientType) // web/electron/flutter
                c.Next()
                return
            }
        }
        
        // 2. API Key（服务端调用）
        apiKey := c.GetHeader("X-API-Key")
        if apiKey != "" {
            if user, err := validateAPIKey(apiKey); err == nil {
                c.Set("user", user)
                c.Next()
                return
            }
        }
        
        c.JSON(http.StatusUnauthorized, gin.H{
            "code": 401,
            "message": "Unauthorized",
        })
        c.Abort()
    }
}
```

### 6.2 客户端类型识别

```go
// 识别客户端类型
func getClientType(c *gin.Context) string {
    // 从 Header 获取
    if clientType := c.GetHeader("X-Client-Type"); clientType != "" {
        return clientType
    }
    
    // 从 User-Agent 识别
    userAgent := c.GetHeader("User-Agent")
    if strings.Contains(userAgent, "Electron") {
        return "electron"
    }
    if strings.Contains(userAgent, "Flutter") {
        return "flutter"
    }
    
    return "web"
}
```

## 7. 推送通知（移动端）

### 7.1 WebSocket 推送

```go
// 实时状态推送
type ClientManager struct {
    clients map[string]map[*websocket.Conn]bool
    broadcast chan []byte
    register chan *websocket.Conn
    unregister chan *websocket.Conn
}

func (cm *ClientManager) run() {
    for {
        select {
        case conn := <-cm.register:
            // 注册客户端
            cm.clients[conn.RemoteAddr().String()] = make(map[*websocket.Conn]bool)
            cm.clients[conn.RemoteAddr().String()][conn] = true
            
        case conn := <-cm.unregister:
            // 注销客户端
            delete(cm.clients, conn.RemoteAddr().String())
            close(conn)
            
        case message := <-cm.broadcast:
            // 广播消息
            for _, conns := range cm.clients {
                for conn := range conns {
                    conn.WriteMessage(websocket.TextMessage, message)
                }
            }
        }
    }
}

// 推送 Wukong 状态更新
func pushWukongStatus(wukongName string, status WukongStatus) {
    message := gin.H{
        "type": "wukong_status",
        "name": wukongName,
        "status": status,
    }
    data, _ := json.Marshal(message)
    clientManager.broadcast <- data
}
```

### 7.2 移动端推送（FCM/APNS）

```go
// 集成 Firebase Cloud Messaging (Android) 和 APNS (iOS)
func sendPushNotification(userID string, title string, body string) {
    // 获取用户的设备 token
    tokens := getUserDeviceTokens(userID)
    
    for _, token := range tokens {
        if token.Platform == "android" {
            sendFCMNotification(token.Token, title, body)
        } else if token.Platform == "ios" {
            sendAPNSNotification(token.Token, title, body)
        }
    }
}
```

## 8. 离线支持（移动端）

### 8.1 本地缓存

```dart
// Flutter 本地缓存
class WukongCache {
  final SharedPreferences _prefs;
  
  Future<void> cacheWukongs(List<Wukong> wukongs) async {
    final json = wukongs.map((w) => w.toJson()).toList();
    await _prefs.setString('wukongs_cache', jsonEncode(json));
  }
  
  Future<List<Wukong>> getCachedWukongs() async {
    final json = _prefs.getString('wukongs_cache');
    if (json == null) return [];
    
    final list = jsonDecode(json) as List;
    return list.map((j) => Wukong.fromJson(j)).toList();
  }
}
```

### 8.2 同步机制

```dart
// 离线操作队列
class OfflineQueue {
  final List<OfflineOperation> _queue = [];
  
  Future<void> addOperation(OfflineOperation op) async {
    _queue.add(op);
    await _saveQueue();
  }
  
  Future<void> sync() async {
    if (!await _isOnline()) return;
    
    for (final op in _queue) {
      try {
        await _executeOperation(op);
        _queue.remove(op);
      } catch (e) {
        // 记录错误，稍后重试
        print('Sync failed: $e');
      }
    }
    
    await _saveQueue();
  }
}
```

## 9. 部署配置

### 9.1 API Service 部署

```yaml
# api-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: novasphere-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: novasphere-api
  template:
    metadata:
      labels:
        app: novasphere-api
    spec:
      containers:
      - name: api
        image: novasphere/api:v1.0.0
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9090
          name: grpc
        env:
        - name: KUBECONFIG
          value: /etc/kubernetes/kubeconfig
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: api-secrets
              key: jwt-secret
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: novasphere-api
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  - port: 9090
    targetPort: 9090
    name: grpc
  selector:
    app: novasphere-api
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: novasphere-api
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/websocket-services: novasphere-api
spec:
  tls:
  - hosts:
    - api.novasphere.io
    secretName: novasphere-api-tls
  rules:
  - host: api.novasphere.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: novasphere-api
            port:
              number: 80
```

## 10. 性能优化

### 10.1 连接池

```go
// Kubernetes 客户端连接池
var k8sClient client.Client

func initK8sClient() {
    config, _ := ctrl.GetConfig()
    k8sClient, _ = client.New(config, client.Options{
        Scheme: scheme.Scheme,
    })
}
```

### 10.2 缓存策略

```go
// Redis 缓存
var redisClient *redis.Client

func getWukongCached(name string) (*vmv1alpha1.Wukong, error) {
    // 从缓存读取
    cached, err := redisClient.Get(ctx, "wukong:"+name).Result()
    if err == nil {
        var wukong vmv1alpha1.Wukong
        json.Unmarshal([]byte(cached), &wukong)
        return &wukong, nil
    }
    
    // 从 Kubernetes 读取
    var wukong vmv1alpha1.Wukong
    if err := k8sClient.Get(ctx, client.ObjectKey{Name: name}, &wukong); err != nil {
        return nil, err
    }
    
    // 写入缓存
    data, _ := json.Marshal(wukong)
    redisClient.Set(ctx, "wukong:"+name, data, 30*time.Second)
    
    return &wukong, nil
}
```

## 11. 监控和日志

### 11.1 请求日志

```go
// 记录所有请求
func loggingMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        
        c.Next()
        
        latency := time.Since(start)
        log.Info("request",
            "method", c.Request.Method,
            "path", c.Request.URL.Path,
            "status", c.Writer.Status(),
            "latency", latency,
            "client_type", getClientType(c),
        )
    }
}
```

### 11.2 指标收集

```go
// Prometheus 指标
var (
    requestsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "api_requests_total",
            Help: "Total number of API requests",
        },
        []string{"method", "endpoint", "client_type", "status"},
    )
    
    requestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "api_request_duration_seconds",
            Help: "API request duration",
        },
        []string{"method", "endpoint", "client_type"},
    )
)
```

## 12. 总结

### 12.1 架构优势

- ✅ **统一 API**：一套 API 服务所有客户端
- ✅ **多协议支持**：RESTful、WebSocket、gRPC
- ✅ **客户端适配**：针对不同客户端优化
- ✅ **离线支持**：移动端离线缓存和同步
- ✅ **推送通知**：实时状态更新
- ✅ **易于扩展**：支持新客户端类型

### 12.2 实施建议

1. **第一阶段**：实现 RESTful API，支持 Web 和 Electron
2. **第二阶段**：添加 WebSocket 支持，实现控制台功能
3. **第三阶段**：添加 Flutter 支持，实现推送和离线功能
4. **第四阶段**：优化性能，添加 gRPC 支持（可选）

