# Traefik Gateway 配置

## 快速部署

```bash
# 使用 Helm（推荐）
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set providers.kubernetesIngress.enabled=true \
  --set providers.kubernetesCRD.enabled=true

# 或使用 kubectl
kubectl apply -k config/gateway/traefik/
```

## 配置文件说明

- `traefik-deployment.yaml`: Traefik 部署配置
- `traefik-service.yaml`: Traefik 服务配置
- `ingressroute.yaml`: IngressRoute CRD 配置
- `middlewares.yaml`: 中间件配置（认证、限流、CORS）

## 验证

```bash
# 检查状态
kubectl get pods -n traefik-system

# 访问 Dashboard
kubectl port-forward -n traefik-system svc/traefik 8080:8080
# 访问 http://localhost:8080/dashboard/
```

