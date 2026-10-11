# DevBoard: Production-Grade Kubernetes & GitOps Deployment Guide

This document is the definitive, production-level guide for deploying, configuring, and operating the **DevBoard** microservices platform on Kubernetes using GitOps (Argo CD). It is designed to ensure zero-error, idempotent deployments across both bare-metal/local clusters (WSL, containerd) and cloud environments (AWS EKS).

---

## 1. System Architecture

The DevBoard application consists of four primary microservices, an in-cluster LLM server, an Envoy-based API Gateway, and managed GitOps automation.

```mermaid
graph TD
    User["User / Web Browser"] -->|Port 80 / NodePort 32395| Gateway["Envoy Gateway Proxy"]
    
    subgraph K8s["Kubernetes Cluster (devboard namespace)"]
        Gateway -->|"/*"| Frontend["Frontend (Vite / React)"]
        Gateway -->|"/api/ai/*" (Rewrite to /)| AIService["AI Service (Python FastAPI)"]
        Frontend -->|Internal Proxy| Backend["Backend API (Go)"]
        Backend --> DB[("PostgreSQL 16 (StatefulSet)")]
        AIService --> Backend
    end

    subgraph Platform["Platform Infra (ollama namespace)"]
        AIService -->|"http://ollama.ollama.svc:11434"| Ollama["Ollama LLM (llama3.2:1b)"]
        Ollama --> ModelVolume[("HostPath: /tmp/ollama-models")]
    end

    subgraph GitOps["GitOps Automation (argocd namespace)"]
        GitRepo["GitHub Repository (gitops branch)"] -->|Watches /k8s| ArgoCD["Argo CD Application Controller"]
        ArgoCD -->|Sync & Self-Heal| K8s
    end
```

---

## 2. Core Components & Manifest Manifests

| Component | Manifest Path | Namespace | Role & Key Configuration |
| :--- | :--- | :--- | :--- |
| **PostgreSQL** | `k8s/postgres-statefulset.yml` | `devboard` | Persistent relational storage. Uses `postgres-pvc` with `storageClassName: manual`. |
| **Backend API** | `k8s/backend-deployment.yml` | `devboard` | Core business logic written in Go. Connects to `postgres:5432`. |
| **Frontend UI** | `k8s/frontend-deployment.yml` | `devboard` | React SPA. Scaled horizontally via `frontend-hpa.yml` (1–5 replicas). |
| **AI Service** | `k8s/ai-service-deployment.yml` | `devboard` | FastAPI inference endpoint. Talks to Ollama via `http://ollama.ollama.svc.cluster.local:11434/v1`. |
| **Ollama LLM** | `k8s/ollama.yml` | `ollama` | Model runner for `llama3.2:1b`. Uses HostPath caching so models persist across pod lifecycles. |
| **Gateway API** | `k8s/gateway.yml` & `httproute.yml` | `devboard` | Envoy Gateway listener + routing rules mapping `/` to Frontend and `/api/ai` to AI Service. |
| **Metrics Server** | `kube-system` | `kube-system` | Provides metrics API for Horizontal Pod Autoscaling (HPA). |

---

## 3. Step-by-Step Zero-Error Deployment

To deploy this project reliably from scratch without encountering common pitfalls, follow this sequence:

### Step 1: Install Platform Prerequisites
Ensure the cluster has Gateway API CRDs, Envoy Gateway, Metrics Server, and Argo CD installed:
```bash
# 1. Gateway API CRDs & Envoy Gateway
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.2.1 -n envoy-gateway-system --create-namespace

# 2. Metrics Server (for HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# On bare-metal / WSL, allow insecure kubelet TLS:
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# 3. Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 2: Prepare Storage & Host Directories
Pre-create the directories on the Kubernetes host to avoid mount permission errors:
```bash
sudo mkdir -p /mnt/devboard-postgres /tmp/ollama-models
sudo chmod -R 777 /mnt/devboard-postgres /tmp/ollama-models
```

### Step 3: Deploy the Core Application via GitOps
Apply the Argo CD application manifest:
```bash
kubectl apply -f gitops/argocd/devboard-application.yml
```

Argo CD will automatically sync all manifests under `k8s/` into the cluster and monitor them with `selfHeal: true`.

---

## 4. Production Hardening & Root-Cause Prevention

### A. Preventing Postgres `Pending` Issues (PV Claim Locking)
* **The Problem:** In Kubernetes, a PersistentVolume with `reclaimPolicy: Retain` enters the `Released` status when a namespace or PVC is deleted. It cannot be bound by a new PVC until the `spec.claimRef` is cleared.
* **The Rule:** If you delete and recreate the `devboard` namespace, run the included repair script:
  ```bash
  bash /devboard-gitops/devboard/fix-postgres.sh
  ```
* **Git Consistency:** Never change PVC names or storage classes directly with `kubectl` without pushing to Git; otherwise, Argo CD's `selfHeal` will revert them back.

### B. Preventing AI Model Re-downloads & DNS Errors
* **The Problem:** Downloading LLMs (1.3 GB – 5 GB) over slow connections causes AI service startup probes to fail with DNS `[Errno -2]` timeouts.
* **The Rule:** The `k8s/ollama.yml` manifest uses a HostPath mount to `/tmp/ollama-models`. The model is pulled once and persisted permanently on the host machine.
* **Verification:** Verify Ollama is ready and loaded before testing the AI endpoint:
  ```bash
  kubectl exec -n ollama deployment/ollama -- ollama list
  # Output must show: llama3.2:1b
  ```

### C. Preventing Envoy Gateway `<pending>` on Bare-Metal / WSL
* **The Problem:** `LoadBalancer` services stay `<pending>` indefinitely in non-cloud environments.
* **The Rule:**
  Assign your host/node IP to the service externalIPs and status so port 80 routes directly:
  ```bash
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  kubectl patch svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=devboard-gateway --subresource=status -p "{\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"$NODE_IP\"}]}}}"
  kubectl patch svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=devboard-gateway -p "{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}"
  ```

---

## 5. Operations & Health Verification Runbook

Run these commands to verify the entire stack is healthy:

```bash
# 1. Check all DevBoard Pods (All must be 1/1 Running)
kubectl get pods -n devboard

# 2. Check Ollama Pod (Must be 1/1 Running)
kubectl get pods -n ollama

# 3. Check Gateway Pod (Must be 2/2 Running)
kubectl get pods -n envoy-gateway-system -l app.kubernetes.io/name=envoy

# 4. Check HPA (TARGETS must show real percentage, e.g. 40%/60%, NOT <unknown>)
kubectl get hpa -n devboard

# 5. Check Argo CD Status (Must show Synced and Healthy)
kubectl get application devboard-gitops-application -n argocd -o jsonpath="Status: {.status.sync.status}, Health: {.status.health.status}"
```

### Testing Application Endpoints:
```bash
# Frontend
curl -I http://172.25.232.68/

# AI Service Health
curl -s http://172.25.232.68/api/ai/health

# AI Streaming Inference
curl -X POST http://172.25.232.68/api/ai/ask \
  -H "Content-Type: application/json" \
  -d '{"project_id":"1","question":"Summarize active tasks"}'
```

---

## 6. Accessing Management UIs
* **DevBoard Web Application:** `http://172.25.232.68/` (or `http://172.25.232.68:32395/`)
* **Argo CD Dashboard:** `http://localhost:8080/`
  * Username: `admin`
  * Password retrieval: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
