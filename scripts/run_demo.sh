#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_DIR="$ROOT_DIR/.demo-pids"
mkdir -p "$PID_DIR"

echo "==> Ensuring kind cluster 'dreamwork' exists"
if ! kind get clusters | awk '$0=="dreamwork"{found=1} END{exit found?0:1}'; then
  kind create cluster --name dreamwork
else
  echo "Cluster already exists."
fi

echo "==> Building core-api image"
docker buildx build --load -t dreamwork/core-api:dev -f "$ROOT_DIR/core/Dockerfile" "$ROOT_DIR/core"

echo "==> Loading image into kind"
kind load docker-image dreamwork/core-api:dev --name dreamwork

echo "==> Applying Kubernetes manifests"
kubectl apply -f "$ROOT_DIR/deploy/k8s/core-api.yaml"
kubectl rollout restart deployment/core-api >/dev/null 2>&1 || true
kubectl rollout status deployment/core-api --timeout=120s

echo "==> Starting background port-forward (18081 -> core-api:8080)"
pkill -f "kubectl port-forward service/core-api 18081:8080" >/dev/null 2>&1 || true
nohup kubectl port-forward service/core-api 18081:8080 > "$PID_DIR/port-forward.log" 2>&1 &
echo $! > "$PID_DIR/port-forward.pid"
sleep 1
curl -s http://127.0.0.1:18081/healthz >/dev/null

echo "==> Starting background demo form server (8000)"
pkill -f "python3 -m http.server 8000" >/dev/null 2>&1 || true
cd "$ROOT_DIR"
nohup python3 -m http.server 8000 > "$PID_DIR/form-server.log" 2>&1 &
echo $! > "$PID_DIR/form-server.pid"

echo "==> Launching iOS Simulator app"
xcodegen generate --spec "$ROOT_DIR/apps/ios/project.yml" >/dev/null
xcrun simctl boot "iPhone 16" >/dev/null 2>&1 || true
open -a Simulator
xcrun simctl launch booted com.dreamwork.app >/dev/null

cat <<EOF

Demo environment is ready.

Open these:
- Demo form: http://127.0.0.1:8000/demo/form/demo-form.html
- Core API health: http://127.0.0.1:18081/healthz

Load Chrome extension from:
- $ROOT_DIR/apps/extension-demo

To stop demo background services:
- $ROOT_DIR/scripts/stop_demo.sh

EOF
