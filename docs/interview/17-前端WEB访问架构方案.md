# 前端 WEB 访问架构方案

## 1. 概述

前端 WEB 访问控制 VM 的架构设计，不推荐直接访问 Controller。

## 2. 方案对比

### 2.1 ❌ 直接访问 Controller（不推荐）

**问题**:
- Controller 是后端服务，不应直接暴露
- 缺少认证授权机制
- 没有 API 网关功能
- 不符合前后端分离架构
- 难以扩展和维护

### 2.2 ✅ 推荐方案

1. **API Gateway + Controller**（推荐）
2. **Kubernetes API Server + RBAC**
3. **专用 API Service**
4. **KubeVirt API 直接访问**

## 3. 方案一：API Gateway + Controller（推荐）

### 3.1 架构说明

**重要说明**：API Gateway 和 API Service 是两个不同的概念：

1. **API Gateway**（不需要开发）
   - 现成的工具：Kong、Traefik、Nginx、Envoy
   - 负责：路由、SSL、认证、限流、监控
   - 部署：直接使用，无需开发

2. **API Service**（可选，根据需求决定）
   - 需要新开发的服务
   - 负责：业务逻辑、数据转换、复杂操作
   - 如果业务简单，可以**不开发**，直接让 API Gateway 代理到 Controller

### 3.2 两种实现方式

#### 方式 A：API Gateway 直接代理 Controller（简单，推荐）

```
前端 (React/Vue)
    ↓ HTTP
API Gateway (Kong/Traefik/Nginx)
    ↓ 认证、授权、限流
Controller (Kubebuilder) - 通过 Kubernetes API
    ↓
Kubernetes API Server
    ↓
KubeVirt + Novasphere CRD
```

**优点**：
- ✅ 不需要开发新服务
- ✅ 架构简单
- ✅ 直接使用 Controller 的功能

**缺点**：
- ❌ Controller 需要暴露 HTTP 接口（需要改造）
- ❌ 业务逻辑耦合在 Controller 中

#### 方式 B：API Gateway + 独立 API Service（复杂，功能完整）

```
前端 (React/Vue)
    ↓ HTTP/WebSocket
API Gateway (Kong/Traefik/Nginx)
    ↓ 认证、授权、限流
API Service (新开发的服务)
    ↓ gRPC/HTTP
Controller (Kubebuilder)
    ↓
Kubernetes API Server
    ↓
KubeVirt + Novasphere CRD
```

**优点**：
- ✅ 前后端完全分离
- ✅ 业务逻辑独立
- ✅ 易于扩展和维护
- ✅ 支持复杂业务逻辑

**缺点**：
- ❌ 需要开发新服务
- ❌ 架构更复杂
- ❌ 需要维护额外服务

### 3.3 推荐选择

**如果业务简单**：使用方式 A（API Gateway 直接代理）
**如果业务复杂**：使用方式 B（开发独立 API Service）

### 3.4 实现方案

#### 3.4.1 方式 A：Controller 暴露 HTTP 接口（简单方案）

**改造 Controller 添加 HTTP Server**：

```go
// internal/controller/wukong_controller.go
package controller

import (
    "github.com/gin-gonic/gin"
    "net/http"
)

type WukongReconciler struct {
    // ... 现有字段
    httpServer *gin.Engine
}

func (r *WukongReconciler) SetupHTTPServer() {
    r.httpServer = gin.Default()
    
    // 认证中间件（从 API Gateway 传递的用户信息）
    r.httpServer.Use(r.authMiddleware())
    
    // API 路由
    api := r.httpServer.Group("/api/v1")
    {
        api.GET("/wukongs", r.listWukongs)
        api.POST("/wukongs", r.createWukong)
        api.GET("/wukongs/:name", r.getWukong)
        api.DELETE("/wukongs/:name", r.deleteWukong)
        api.POST("/wukongs/:name/start", r.startWukong)
        api.POST("/wukongs/:name/stop", r.stopWukong)
    }
    
    // 启动 HTTP 服务器
    go func() {
        if err := r.httpServer.Run(":8080"); err != nil {
            log.Error(err, "HTTP server failed")
        }
    }()
}

func (r *WukongReconciler) listWukongs(c *gin.Context) {
    var wukongs vmv1alpha1.WukongList
    if err := r.List(c.Request.Context(), &wukongs); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.JSON(http.StatusOK, wukongs.Items)
}

func (r *WukongReconciler) createWukong(c *gin.Context) {
    var wukong vmv1alpha1.Wukong
    if err := c.ShouldBindJSON(&wukong); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    if err := r.Create(c.Request.Context(), &wukong); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    
    c.JSON(http.StatusCreated, wukong)
}
```

**API Gateway 配置（Traefik 示例）**：

```yaml
# traefik-config.yaml
apiVersion: v1
kind: Service
metadata:
  name: novasphere-controller
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
    traefik.ingress.kubernetes.io/router.middlewares: default-auth@kubernetescrd
spec:
  selector:
    control-plane: controller-manager
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: auth
spec:
  forwardAuth:
    address: "http://auth-service:8080/auth"
    authResponseHeaders:
      - "X-User-Id"
      - "X-User-Name"
```

#### 3.4.2 方式 B：独立 API Service 设计（完整方案）

```go
// pkg/api/server.go
package api

import (
    "context"
    "net/http"
    
    "github.com/gin-gonic/gin"
    "k8s.io/client-go/kubernetes"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

type APIServer struct {
    k8sClient client.Client
    router    *gin.Engine
}

func NewAPIServer(k8sClient client.Client) *APIServer {
    router := gin.Default()
    
    // 认证中间件
    router.Use(authMiddleware())
    
    // API 路由
    api := router.Group("/api/v1")
    {
        api.GET("/wukongs", listWukongs)
        api.POST("/wukongs", createWukong)
        api.GET("/wukongs/:name", getWukong)
        api.PUT("/wukongs/:name", updateWukong)
        api.DELETE("/wukongs/:name", deleteWukong)
        api.POST("/wukongs/:name/start", startWukong)
        api.POST("/wukongs/:name/stop", stopWukong)
        api.GET("/wukongs/:name/console", getConsoleURL)
    }
    
    return &APIServer{
        k8sClient: k8sClient,
        router:    router,
    }
}

func (s *APIServer) Start(addr string) error {
    return s.router.Run(addr)
}
```

#### 3.3.2 API 接口设计

```go
// GET /api/v1/wukongs
func listWukongs(c *gin.Context) {
    var wukongs vmv1alpha1.WukongList
    if err := k8sClient.List(ctx, &wukongs); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.JSON(http.StatusOK, wukongs.Items)
}

// POST /api/v1/wukongs
func createWukong(c *gin.Context) {
    var wukong vmv1alpha1.Wukong
    if err := c.ShouldBindJSON(&wukong); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    // 验证和默认值设置
    if err := validateWukong(&wukong); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    if err := k8sClient.Create(ctx, &wukong); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    
    c.JSON(http.StatusCreated, wukong)
}

// POST /api/v1/wukongs/:name/start
func startWukong(c *gin.Context) {
    name := c.Param("name")
    
    var wukong vmv1alpha1.Wukong
    if err := k8sClient.Get(ctx, client.ObjectKey{Name: name}, &wukong); err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "Wukong not found"})
        return
    }
    
    // 更新 Wukong 启动 VM
    wukong.Spec.StartStrategy.AutoStart = true
    if err := k8sClient.Update(ctx, &wukong); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    
    c.JSON(http.StatusOK, gin.H{"message": "Wukong started"})
}
```

### 3.4 认证授权

#### 3.4.1 JWT 认证
```go
func authMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if token == "" {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
            c.Abort()
            return
        }
        
        // 验证 JWT token
        claims, err := validateJWT(token)
        if err != nil {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
            c.Abort()
            return
        }
        
        c.Set("user", claims.User)
        c.Next()
    }
}
```

#### 3.4.2 RBAC 授权
```go
func checkPermission(user string, action string, resource string) bool {
    // 检查用户权限
    // 可以集成 Kubernetes RBAC
    return true
}
```

## 4. 方案二：Kubernetes API Server + RBAC

### 4.1 架构图

```
前端 (React/Vue)
    ↓
Kubernetes Dashboard / 自定义前端
    ↓
Kubernetes API Server
    ↓ (RBAC 授权)
KubeVirt + Novasphere CRD
```

### 4.2 优势

- ✅ 直接使用 Kubernetes 原生 API
- ✅ 利用 Kubernetes RBAC
- ✅ 无需额外 API 层

### 4.3 实现方案

#### 4.3.1 使用 Kubernetes Dashboard
```yaml
# 部署 Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# 创建 ServiceAccount 和 RBAC
apiVersion: v1
kind: ServiceAccount
metadata:
  name: novasphere-user
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: novasphere-user
rules:
- apiGroups: ["vm.novasphere.dev"]
  resources: ["wukongs"]
  verbs: ["get", "list", "create", "update", "delete", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: novasphere-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: novasphere-user
subjects:
- kind: ServiceAccount
  name: novasphere-user
  namespace: default
```

#### 4.3.2 前端直接调用 Kubernetes API
```javascript
// 前端代码
const k8s = require('@kubernetes/client-node');

const kc = new k8s.KubeConfig();
kc.loadFromDefault();

const k8sApi = kc.makeApiClient(k8s.CustomObjectsApi);

// 列出 Wukong
async function listWukongs() {
    const response = await k8sApi.listNamespacedCustomObject(
        'vm.novasphere.dev',
        'v1alpha1',
        'default',
        'wukongs'
    );
    return response.body;
}

// 创建 Wukong
async function createWukong(wukong) {
    const response = await k8sApi.createNamespacedCustomObject(
        'vm.novasphere.dev',
        'v1alpha1',
        'default',
        'wukongs',
        wukong
    );
    return response.body;
}
```

## 5. 方案三：专用 API Service

### 5.1 架构图

```
前端 (React/Vue)
    ↓ HTTP
API Service (独立服务)
    ↓
Controller (Kubebuilder)
    ↓
Kubernetes API Server
```

### 5.2 实现方案

将 API Service 作为独立服务部署：

```yaml
# api-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: novasphere-api
spec:
  replicas: 2
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
        image: novasphere/api:latest
        ports:
        - containerPort: 8080
        env:
        - name: KUBECONFIG
          value: /etc/kubernetes/kubeconfig
---
apiVersion: v1
kind: Service
metadata:
  name: novasphere-api
spec:
  selector:
    app: novasphere-api
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: novasphere-api
spec:
  rules:
  - host: api.novasphere.local
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

## 6. 方案四：KubeVirt API 直接访问

### 6.1 架构图

```
前端 (React/Vue)
    ↓
KubeVirt API (virt-api)
    ↓
KubeVirt Controller
    ↓
Kubernetes API Server
```

### 6.2 实现方案

使用 KubeVirt 的 subresource API：

```javascript
// 前端直接调用 KubeVirt API
async function startVM(vmName) {
    const response = await fetch(
        `/apis/subresources.kubevirt.io/v1/namespaces/default/virtualmachines/${vmName}/start`,
        {
            method: 'PUT',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            }
        }
    );
    return response.json();
}
```

## 7. 推荐方案对比

| 方案 | 复杂度 | 功能 | 安全性 | 推荐度 |
|------|-------|------|--------|--------|
| API Gateway + Controller | 中 | 高 | 高 | ⭐⭐⭐⭐⭐ |
| Kubernetes API + RBAC | 低 | 中 | 高 | ⭐⭐⭐⭐ |
| 专用 API Service | 中 | 高 | 中 | ⭐⭐⭐ |
| KubeVirt API 直接访问 | 低 | 低 | 中 | ⭐⭐ |

## 8. 最终推荐方案

### 8.1 方案对比总结

| 方案 | 是否需要开发新服务 | 复杂度 | 适用场景 |
|------|------------------|--------|---------|
| **方式 A：API Gateway 直接代理 Controller** | ❌ 不需要 | 低 | 业务简单，快速上线 |
| **方式 B：API Gateway + 独立 API Service** | ✅ 需要 | 中 | 业务复杂，需要扩展 |

### 8.2 推荐：方式 A（简单方案）

**完整架构**：

```
用户浏览器
    ↓ HTTPS
Nginx/Traefik (反向代理 + SSL)
    ↓
API Gateway (Kong/Traefik)
    ├── 认证 (JWT/OAuth2)
    ├── 授权 (RBAC)
    ├── 限流
    └── 监控
    ↓
Controller (Kubebuilder) - 添加 HTTP 接口
    ↓
Kubernetes API Server
    ↓
KubeVirt + Novasphere CRD
```

**优点**：
- ✅ 不需要开发新服务
- ✅ 架构简单，维护成本低
- ✅ 直接使用 Controller 功能
- ✅ 快速上线

**实现要点**：
1. Controller 添加 HTTP Server（如 Gin）
2. API Gateway 配置路由到 Controller
3. API Gateway 处理认证授权
4. Controller 处理业务逻辑

### 8.3 备选：方式 B（完整方案）

**完整架构**：

```
用户浏览器
    ↓ HTTPS
Nginx/Traefik (反向代理 + SSL)
    ↓
API Gateway (Kong/Envoy)
    ├── 认证 (JWT/OAuth2)
    ├── 授权 (RBAC)
    ├── 限流
    └── 监控
    ↓
API Service (新开发的服务)
    ├── RESTful API
    ├── WebSocket (控制台)
    └── 业务逻辑
    ↓
Controller (Kubebuilder)
    ↓
Kubernetes API Server
    ↓
KubeVirt + Novasphere CRD
```

**适用场景**：
- 需要复杂的业务逻辑
- 需要 WebSocket 支持（控制台）
- 需要数据聚合、转换
- 需要多客户端支持

### 8.4 部署示例

#### 方式 A：Controller 暴露 HTTP 接口

```yaml
# Controller 已包含 HTTP Server，只需配置 Service 和 Ingress
apiVersion: v1
kind: Service
metadata:
  name: novasphere-controller
spec:
  selector:
    control-plane: controller-manager
  ports:
  - port: 8080
    targetPort: 8080
    name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: novasphere-api
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: default-auth@kubernetescrd
    cert-manager.io/cluster-issuer: letsencrypt-prod
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
            name: novasphere-controller
            port:
              number: 8080
```

#### 方式 B：独立 API Service

```yaml
# 需要单独部署 API Service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: novasphere-api
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: api
        image: novasphere/api:v1.0.0
        env:
        - name: KUBECONFIG
          value: /etc/kubernetes/kubeconfig
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: api-secrets
              key: jwt-secret
---
apiVersion: v1
kind: Service
metadata:
  name: novasphere-api
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: novasphere-api
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
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
              number: 8080
```

## 9. 前端集成示例

### 9.1 React 示例
```typescript
// api/client.ts
import axios from 'axios';

const apiClient = axios.create({
  baseURL: 'https://api.novasphere.io/api/v1',
  headers: {
    'Content-Type': 'application/json',
  },
});

// 添加认证拦截器
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// API 方法
export const wukongAPI = {
  list: () => apiClient.get('/wukongs'),
  get: (name: string) => apiClient.get(`/wukongs/${name}`),
  create: (wukong: any) => apiClient.post('/wukongs', wukong),
  update: (name: string, wukong: any) => apiClient.put(`/wukongs/${name}`, wukong),
  delete: (name: string) => apiClient.delete(`/wukongs/${name}`),
  start: (name: string) => apiClient.post(`/wukongs/${name}/start`),
  stop: (name: string) => apiClient.post(`/wukongs/${name}/stop`),
  getConsole: (name: string) => apiClient.get(`/wukongs/${name}/console`),
};
```

## 10. 总结和建议

### 10.1 关键点澄清

1. **API Gateway**：
   - ✅ 现成工具（Kong、Traefik、Nginx）
   - ✅ 不需要开发
   - ✅ 负责路由、认证、限流

2. **API Service**：
   - ❓ 可选，根据需求决定
   - ✅ 如果业务简单：**不需要开发**，直接让 Controller 暴露 HTTP 接口
   - ✅ 如果业务复杂：**需要开发**，作为独立服务

### 10.2 推荐方案

**对于大多数场景，推荐方式 A**：
- Controller 添加 HTTP Server（简单改造）
- API Gateway 直接代理到 Controller
- 不需要开发新服务
- 架构简单，维护成本低

**如果未来需要复杂功能，再考虑方式 B**：
- 开发独立的 API Service
- 支持 WebSocket、复杂业务逻辑等

### 10.3 注意事项

- ✅ 不要直接暴露 Controller 给前端（无认证）
- ✅ 使用 API Gateway 统一管理（认证、限流、监控）
- ✅ 实现认证授权机制（JWT/OAuth2）
- ✅ 支持 WebSocket（控制台访问，方式 B 支持更好）
- ✅ 添加限流和监控
- ✅ 使用 HTTPS

