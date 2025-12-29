# API Gateway 网关方案实现

## 1. 概述

使用 Kong 或 Traefik 作为 API Gateway，**不需要新建项目**，只需在现有项目中添加配置和部署文件。

## 2. 项目结构

### 2.1 不需要新建项目

在现有 `vmoperator` 项目中添加：

```
vmoperator/
├── config/
│   ├── gateway/              # 新增：网关配置
│   │   ├── kong/            # Kong 配置
│   │   │   ├── kong.yaml
│   │   │   └── kustomization.yaml
│   │   └── traefik/         # Traefik 配置
│   │       ├── traefik.yaml
│   │       └── kustomization.yaml
│   └── ...
├── charts/                   # 如果使用 Helm
│   └── novasphere/
│       └── templates/
│           └── gateway/     # 网关模板
└── ...
```

## 3. Kong 网关方案

### 3.1 Kong 简介

- **类型**：云原生 API Gateway
- **特点**：插件丰富、性能高、支持多种协议
- **部署**：支持 Kubernetes、Docker

### 3.2 架构

```
前端
    ↓
Kong Gateway
    ├── 认证插件 (JWT/OAuth2)
    ├── 限流插件
    ├── 日志插件
    └── 监控插件
    ↓
novasphere-api (或 Controller)
```

### 3.3 部署方案

#### 方案 A：使用 Kong Ingress Controller（推荐）

```yaml
# config/gateway/kong/kong-ingress.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kong-system
---
# 安装 Kong Ingress Controller
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kong-serviceaccount
  namespace: kong-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kong-ingress-clusterrole
rules:
- apiGroups:
  - ""
  resources:
  - services
  - endpoints
  - nodes
  - pods
  - secrets
  verbs:
  - list
  - watch
- apiGroups:
  - extensions
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kong-ingress-clusterrolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kong-ingress-clusterrole
subjects:
- kind: ServiceAccount
  name: kong-serviceaccount
  namespace: kong-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kong
  namespace: kong-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kong
  template:
    metadata:
      labels:
        app: kong
    spec:
      serviceAccountName: kong-serviceaccount
      containers:
      - name: proxy
        image: kong:3.4
        env:
        - name: KONG_DATABASE
          value: "off"  # 使用 DB-less 模式
        - name: KONG_DECLARATIVE_CONFIG
          value: /kong/declarative/kong.yml
        - name: KONG_PROXY_ACCESS_LOG
          value: /dev/stdout
        - name: KONG_ADMIN_ACCESS_LOG
          value: /dev/stdout
        - name: KONG_PROXY_ERROR_LOG
          value: /dev/stderr
        - name: KONG_ADMIN_ERROR_LOG
          value: /dev/stderr
        - name: KONG_ADMIN_LISTEN
          value: 0.0.0.0:8001
        ports:
        - containerPort: 8000
          name: proxy
        - containerPort: 8443
          name: proxy-ssl
        - containerPort: 8001
          name: admin
        volumeMounts:
        - name: kong-config
          mountPath: /kong/declarative
      volumes:
      - name: kong-config
        configMap:
          name: kong-config
---
apiVersion: v1
kind: Service
metadata:
  name: kong-proxy
  namespace: kong-system
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8000
    protocol: TCP
    name: proxy
  - port: 443
    targetPort: 8443
    protocol: TCP
    name: proxy-ssl
  selector:
    app: kong
```

#### 方案 B：使用 Kong Helm Chart

```yaml
# config/gateway/kong/kong-values.yaml
# 用于 Helm 安装 Kong

deployment:
  kong:
    enabled: true
    image:
      repository: kong
      tag: "3.4"
    env:
      database: "off"  # DB-less 模式
      declarative_config: /kong/declarative/kong.yml
    service:
      type: LoadBalancer
      http:
        enabled: true
        servicePort: 80
        containerPort: 8000
      tls:
        enabled: true
        servicePort: 443
        containerPort: 8443

ingressController:
  enabled: true
  installCRDs: true
```

### 3.4 Kong 配置

```yaml
# config/gateway/kong/kong-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kong-config
  namespace: kong-system
data:
  kong.yml: |
    _format_version: "3.0"
    
    # 服务定义
    services:
    - name: novasphere-api
      url: http://novasphere-api.novasphere-system.svc.cluster.local:8080
      routes:
      - name: novasphere-api-route
        paths:
        - /api/v1
        strip_path: false
        preserve_host: true
    
    # 插件配置
    plugins:
    # JWT 认证
    - name: jwt
      service: novasphere-api
      config:
        secret_is_base64: false
        uri_param_names:
        - token
        claims_to_verify:
        - exp
        key_claim_name: iss
    
    # 限流
    - name: rate-limiting
      service: novasphere-api
      config:
        minute: 100
        hour: 1000
        policy: local
    
    # CORS
    - name: cors
      service: novasphere-api
      config:
        origins:
        - "*"
        methods:
        - GET
        - POST
        - PUT
        - DELETE
        - OPTIONS
        headers:
        - Accept
        - Accept-Version
        - Content-Length
        - Content-MD5
        - Content-Type
        - Date
        - Authorization
        exposed_headers:
        - X-Auth-Token
        credentials: true
        max_age: 3600
    
    # 请求日志
    - name: file-log
      service: novasphere-api
      config:
        path: /tmp/kong-access.log
        reopen: true
    
    # 请求转换（添加客户端类型）
    - name: request-transformer
      service: novasphere-api
      config:
        add:
          headers:
          - "X-Forwarded-By:kong"
```

### 3.5 Ingress 配置

```yaml
# config/gateway/kong/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: novasphere-api
  namespace: novasphere-system
  annotations:
    konghq.com/plugins: jwt-auth,rate-limiting,cors
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: kong
  tls:
  - hosts:
    - api.novasphere.io
    secretName: novasphere-api-tls
  rules:
  - host: api.novasphere.io
    http:
      paths:
      - path: /api/v1
        pathType: Prefix
        backend:
          service:
            name: novasphere-api
            port:
              number: 8080
```

### 3.6 JWT 认证配置

```yaml
# config/gateway/kong/jwt-consumer.yaml
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: novasphere-user
  namespace: kong-system
username: novasphere-user
credentials:
- jwt-secret
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: jwt-auth
  namespace: kong-system
plugin: jwt
config:
  key_claim_name: iss
  secret_is_base64: false
---
apiVersion: configuration.konghq.com/v1
kind: KongCredential
metadata:
  name: jwt-secret
  namespace: kong-system
consumerRef: novasphere-user
type: jwt
config:
  algorithm: HS256
  secret: your-jwt-secret-key
```

### 3.7 部署命令

```bash
# 方式 1: 使用 Helm
helm repo add kong https://charts.konghq.com
helm repo update
helm install kong kong/kong \
  --namespace kong-system \
  --create-namespace \
  -f config/gateway/kong/kong-values.yaml

# 方式 2: 使用 kubectl
kubectl apply -f config/gateway/kong/

# 应用配置
kubectl apply -f config/gateway/kong/kong-config.yaml
kubectl apply -f config/gateway/kong/ingress.yaml
```

## 4. Traefik 网关方案

### 4.1 Traefik 简介

- **类型**：云原生反向代理和负载均衡器
- **特点**：自动服务发现、Let's Encrypt 集成、配置简单
- **部署**：原生支持 Kubernetes

### 4.2 架构

```
前端
    ↓
Traefik
    ├── 中间件 (认证、限流)
    ├── 自动 SSL
    └── 服务发现
    ↓
novasphere-api (或 Controller)
```

### 4.3 部署方案

#### 方案 A：使用 Traefik Helm Chart（推荐）

```yaml
# config/gateway/traefik/traefik-values.yaml
# 用于 Helm 安装 Traefik

deployment:
  replicas: 2

ports:
  web:
    port: 80
    exposedPort: 80
  websecure:
    port: 443
    exposedPort: 443
  traefik:
    port: 9000
    exposedPort: 9000

ingressRoute:
  dashboard:
    enabled: true

providers:
  kubernetesIngress:
    enabled: true
    allowExternalNameServices: true
  kubernetesCRD:
    enabled: true
    allowExternalNameServices: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@novasphere.io
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web

additionalArguments:
  - "--api.insecure=true"
  - "--log.level=INFO"
  - "--accesslog=true"
  - "--metrics.prometheus=true"
```

#### 方案 B：使用 Traefik Operator

```yaml
# config/gateway/traefik/traefik-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: traefik-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik
      containers:
      - name: traefik
        image: traefik:v3.0
        args:
        - --api.insecure=true
        - --providers.kubernetesingress=true
        - --providers.kubernetescrd=true
        - --entrypoints.web.address=:80
        - --entrypoints.websecure.address=:443
        - --certificatesresolvers.letsencrypt.acme.email=admin@novasphere.io
        - --certificatesresolvers.letsencrypt.acme.storage=/data/acme.json
        - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
        ports:
        - containerPort: 80
          name: web
        - containerPort: 443
          name: websecure
        - containerPort: 8080
          name: admin
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: traefik-system
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    name: web
  - port: 443
    targetPort: 443
    name: websecure
  selector:
    app: traefik
```

### 4.4 IngressRoute 配置

```yaml
# config/gateway/traefik/ingressroute.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: novasphere-api
  namespace: novasphere-system
spec:
  entryPoints:
  - web
  - websecure
  routes:
  - match: Host(`api.novasphere.io`) && PathPrefix(`/api/v1`)
    kind: Rule
    services:
    - name: novasphere-api
      port: 8080
    middlewares:
    - name: auth
    - name: rate-limit
    - name: cors
  tls:
    certResolver: letsencrypt
---
# 认证中间件
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: auth
  namespace: novasphere-system
spec:
  forwardAuth:
    address: http://auth-service:8080/auth
    authResponseHeaders:
    - X-User-Id
    - X-User-Name
    - X-Client-Type
---
# 限流中间件
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: novasphere-system
spec:
  rateLimit:
    average: 100
    period: 1m
    burst: 200
---
# CORS 中间件
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: cors
  namespace: novasphere-system
spec:
  headers:
    accessControlAllowMethods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS
    accessControlAllowOriginList:
    - "*"
    accessControlAllowHeaders:
    - Content-Type
    - Authorization
    accessControlMaxAge: 3600
    addVaryHeader: true
```

### 4.5 JWT 认证中间件

```yaml
# config/gateway/traefik/jwt-middleware.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: jwt-auth
  namespace: novasphere-system
spec:
  plugin:
    jwt:
      secret: your-jwt-secret-key
      algorithm: HS256
      claims:
        - iss
        - exp
```

### 4.6 部署命令

```bash
# 方式 1: 使用 Helm
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  -f config/gateway/traefik/traefik-values.yaml

# 方式 2: 使用 kubectl
kubectl apply -f config/gateway/traefik/

# 应用配置
kubectl apply -f config/gateway/traefik/ingressroute.yaml
```

## 5. 两种方案对比

| 特性 | Kong | Traefik |
|------|------|---------|
| **配置方式** | YAML 声明式 | IngressRoute CRD |
| **插件生态** | 丰富的插件 | 原生中间件 |
| **自动 SSL** | 需要插件 | 原生支持 |
| **服务发现** | 需要配置 | 自动发现 |
| **学习曲线** | 中等 | 简单 |
| **性能** | 高 | 高 |
| **推荐场景** | 需要丰富插件 | 简单快速部署 |

## 6. 推荐方案

### 6.1 简单场景：Traefik（推荐）

**优势**：
- ✅ 配置简单
- ✅ 自动服务发现
- ✅ 原生 SSL 支持
- ✅ 与 Kubernetes 集成好

**适用**：
- 快速部署
- 标准需求
- 团队熟悉 Kubernetes

### 6.2 复杂场景：Kong

**优势**：
- ✅ 插件丰富
- ✅ 功能强大
- ✅ 企业级特性

**适用**：
- 需要复杂认证
- 需要 API 管理
- 需要高级限流

## 7. 实施步骤

### 7.1 在现有项目中添加配置

```bash
# 1. 创建网关配置目录
mkdir -p config/gateway/{kong,traefik}

# 2. 添加配置文件（见上面的示例）

# 3. 部署网关
# Kong
kubectl apply -f config/gateway/kong/

# 或 Traefik
kubectl apply -f config/gateway/traefik/
```

### 7.2 更新 Makefile（可选）

```makefile
# Makefile 添加网关相关命令

.PHONY: deploy-gateway-kong
deploy-gateway-kong: ## Deploy Kong Gateway
	kubectl apply -f config/gateway/kong/

.PHONY: deploy-gateway-traefik
deploy-gateway-traefik: ## Deploy Traefik Gateway
	kubectl apply -f config/gateway/traefik/

.PHONY: undeploy-gateway-kong
undeploy-gateway-kong: ## Undeploy Kong Gateway
	kubectl delete -f config/gateway/kong/

.PHONY: undeploy-gateway-traefik
undeploy-gateway-traefik: ## Undeploy Traefik Gateway
	kubectl delete -f config/gateway/traefik/
```

## 8. 验证部署

### 8.1 Kong 验证

```bash
# 检查 Kong 状态
kubectl get pods -n kong-system

# 访问 Kong Admin API
kubectl port-forward -n kong-system svc/kong-proxy 8001:8001
curl http://localhost:8001/services

# 测试代理
curl -H "Host: api.novasphere.io" http://localhost:8000/api/v1/wukongs
```

### 8.2 Traefik 验证

```bash
# 检查 Traefik 状态
kubectl get pods -n traefik-system

# 访问 Traefik Dashboard
kubectl port-forward -n traefik-system svc/traefik 8080:8080
# 访问 http://localhost:8080/dashboard/

# 测试代理
curl -H "Host: api.novasphere.io" http://localhost/api/v1/wukongs
```

## 9. 总结

- ✅ **不需要新建项目**，在现有项目中添加配置即可
- ✅ **Kong**：功能强大，插件丰富，适合复杂场景
- ✅ **Traefik**：配置简单，自动发现，适合快速部署
- ✅ 两种方案都支持 Kubernetes 原生集成
- ✅ 都支持 JWT 认证、限流、SSL 等特性
- ✅ **都完全支持流式数据代理**（SSE、WebSocket、流式 HTTP）

## 10. 流式数据支持

### 10.1 支持情况

**Kong 和 Traefik 都完全支持流式数据代理**：
- ✅ **SSE (Server-Sent Events)**：自动支持，无需特殊配置
- ✅ **WebSocket**：需要简单配置
- ✅ **流式 HTTP 响应**：自动支持

### 10.2 Kong 配置

```yaml
# SSE 和流式 HTTP 自动支持
services:
- name: novasphere-api
  url: http://novasphere-api:8080
  routes:
  - paths:
    - /api/v1
    strip_path: false  # 重要：保留路径

# WebSocket 需要配置协议
routes:
- paths:
  - /ws
  protocols:
  - http
  - https
```

### 10.3 Traefik 配置

```yaml
# SSE 和流式 HTTP 自动支持
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
spec:
  routes:
  - services:
    - name: novasphere-api
      port: 8080
      responseForwarding:
        flushInterval: 100ms  # 流式传输刷新间隔

# WebSocket 使用注解
metadata:
  annotations:
    traefik.ingress.kubernetes.io/websocket-services: novasphere-api
```

详细说明请参考：[23-网关流式数据代理详解.md](./23-网关流式数据代理详解.md)

