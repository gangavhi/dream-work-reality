# Local Kubernetes deployment (Docker + kind)

## 1) Install kind

```bash
brew install kind
```

## 2) Create cluster

```bash
kind create cluster --name dreamwork
```

## 3) Build and load image

```bash
docker build -t dreamwork/core-api:dev -f core/Dockerfile core
kind load docker-image dreamwork/core-api:dev --name dreamwork
```

## 4) Deploy

```bash
kubectl apply -f deploy/k8s/core-api.yaml
kubectl rollout status deployment/core-api
```

## 5) Verify

```bash
kubectl port-forward service/core-api 8080:8080
curl http://127.0.0.1:8080/healthz
```
