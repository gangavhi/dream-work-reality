# End-to-end demo: Simulator + Kubernetes core + browser autofill

This runbook gives a repeatable local demo:

1. iOS Simulator app (Rust FFI save/read)
2. Core API running in Kubernetes on Docker (`kind`)
3. Browser form autofill via demo Chrome extension

---

## A) Prerequisites

- Docker Desktop running
- `kind`, `kubectl`, `xcodegen`, Xcode installed
- Rust toolchain installed (`rustup`)

### Fast path (single command)

```bash
./scripts/run_demo.sh
```

This sets up cluster/image/deploy, starts port-forward and demo form server, and launches the iOS app in Simulator.

---

## B) Start / verify Kubernetes core service

From repo root:

```bash
# 1) Create cluster (first time only)
kind create cluster --name dreamwork

# 2) Build image and load into kind
docker buildx build --load -t dreamwork/core-api:dev -f core/Dockerfile core
kind load docker-image dreamwork/core-api:dev --name dreamwork

# 3) Deploy
kubectl apply -f deploy/k8s/core-api.yaml
kubectl rollout status deployment/core-api --timeout=120s
kubectl get pods -l app=core-api
```

Expected pod state: `1/1 Running`.

---

## C) Port-forward core API for browser extension

In terminal tab #1:

```bash
kubectl port-forward service/core-api 18081:8080
```

Quick check from terminal tab #2:

```bash
curl http://127.0.0.1:18081/healthz
```

Expected:

```json
{"status":"ok"}
```

---

## D) Launch and test iOS Simulator app

From repo root:

```bash
# Generate project and run tests
xcodegen generate --spec apps/ios/project.yml
xcodebuild \
  -project apps/ios/DreamWorkApp.xcodeproj \
  -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test

# Launch app in simulator
xcrun simctl boot "iPhone 16" || true
open -a Simulator
xcrun simctl launch booted com.dreamwork.app
```

In app:

- Go to **People** tab
- Tap **Save + Load Demo Person**
- Verify:
  - `Loaded person: Alex Carter`
  - manual entry count increases (Rust-backed in-memory store)

---

## E) Start local form site for browser demo

From repo root:

```bash
python3 -m http.server 8000
```

Open:

- <http://127.0.0.1:8000/demo/form/demo-form.html>

---

## F) Load demo browser extension

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select folder `apps/extension-demo`

---

## G) Demo browser autofill flow

With form tab active:

1. Click extension icon
2. Click **Seed Person in Core API**
3. Click **Fill Active Form**

Expected:

- `Student Full Name` => `Alex Carter`
- guardian and address fields auto-populated
- policy/provider fields populated

---

## H) Demo upload artifacts

Use these files for upload/ingest demos:

- `demo/sample-documents/person-alex-profile.json`
- `demo/sample-documents/school-intake-demo.csv`
- `demo/sample-documents/notes-manual-entry.txt`

All are synthetic and safe for local demos.

---

## I) One-command quick smoke checks

```bash
# core rust tests
source "$HOME/.cargo/env" && cd core && cargo test --workspace

# protocol checks
python3 integration/validate_protocol.py
python3 -m unittest discover -s integration/tests -p "test_*.py"
```

## J) Stop background demo services

```bash
./scripts/stop_demo.sh
```
