# Kong Gateway 配置

## 快速部署

```bash
# 使用 Helm（推荐）
helm repo add kong https://charts.konghq.com
helm repo update
helm install kong kong/kong \
  --namespace kong-system \
  --create-namespace \
  --set deployment.kong.env.database=off \
  --set deployment.kong.env.declarative_config=/kong/declarative/kong.yml

# 或使用 kubectl
kubectl apply -k config/gateway/kong/
```

## 配置文件说明

- `kong-deployment.yaml`: Kong 部署配置
- `kong-service.yaml`: Kong 服务配置
- `kong-config.yaml`: Kong 声明式配置（路由、插件）
- `ingress.yaml`: Kubernetes Ingress 配置

## 验证

```bash
# 检查状态
kubectl get pods -n kong-system

# 访问 Admin API
kubectl port-forward -n kong-system svc/kong-proxy 8001:8001
curl http://localhost:8001/services
```

