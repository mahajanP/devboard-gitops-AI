# Devboard Application Access Guide

## Current Status
✅ Application is **RUNNING AND ACCESSIBLE**

## How to Access

### Option 1: NodePort (Currently Available) ✅
```
http://172.25.232.68:31385/
```
- Service: `envoy-devboard-devboard-gateway-bee4af0f` (LoadBalancer)
- Port: 31385 (mapped to 80)
- **This is the current way to access the application**

### Option 2: LoadBalancer (Pending)
```
http://<EXTERNAL-IP>:80/
```
- Status: **<pending>** (waiting for LoadBalancer controller)
- In EKS, this would get an AWS NLB IP automatically
- In local/minikube, it stays pending and uses NodePort instead

## Verification

```bash
# Check service status
kubectl get svc -n envoy-gateway-system | grep envoy-devboard

# Check gateway status
kubectl get gateway devboard-gateway -n devboard

# Test access
curl http://172.25.232.68:31385/
# Expected: 200 OK

# Check HTTPRoute
kubectl get httproute devboard-route -n devboard -o wide
```

## Architecture

```
User Request
    ↓
http://172.25.232.68:31385/
    ↓
Kubernetes NodePort 31385
    ↓
Envoy Proxy (Gateway API)
    ↓
HTTPRoute (devboard-route)
    ├─→ /api/ai → ai-service:3005
    └─→ / → devboard-frontend-service:8080
            ↓
        Frontend Vite App
```

## Service Details

| Service | Type | Cluster IP | Port | Access |
|---------|------|-----------|------|--------|
| devboard-frontend-service | ClusterIP | 10.107.171.36 | 8080 | Internal only |
| ai-service | ClusterIP | 10.102.41.126 | 3005 | Internal only → Gateway routes `/api/ai` |
| envoy-devboard-gateway | LoadBalancer | 10.100.178.33 | 80 (port 31385 NodePort) | External via NodePort |

## Gateway Status Explanation

| Component | Status | Details |
|-----------|--------|---------|
| **Listener** | ✅ Programmed | Translating listener config to Envoy proxy |
| **Gateway** | ⚠️ Not Programmed | AddressNotAssigned (LoadBalancer IP pending) |
| **HTTPRoute** | ✅ Accepted | Traffic routing configured and working |

**Why is Gateway not Programmed?**
- The LoadBalancer service `envoy-devboard-devboard-gateway-bee4af0f` is in `<pending>` state
- This happens because the environment doesn't have a LoadBalancer controller
- Kubernetes automatically creates a NodePort (31385) as fallback
- The gateway is functional via NodePort even if not "Programmed" with external IP

## Frontend Access

**Direct Frontend (via NodePort):**
```bash
http://172.25.232.68:31385/
```

**Backend API (via Gateway):**
```bash
# Projects API
http://172.25.232.68:31385/api/projects

# AI Service
http://172.25.232.68:31385/api/ai
```

## Troubleshooting

### If application not responding:

1. Check frontend pod is running:
   ```bash
   kubectl get pod -n devboard -l app=devboard-frontend
   ```

2. Check gateway listener:
   ```bash
   kubectl describe gateway devboard-gateway -n devboard
   ```

3. Check route is attached:
   ```bash
   kubectl get httproute -n devboard
   ```

4. Check envoy proxy pod:
   ```bash
   kubectl get pod -n envoy-gateway-system -l app.kubernetes.io/name=envoy
   ```

5. Check service selector:
   ```bash
   kubectl get svc devboard-frontend-service -n devboard -o yaml | grep -A 5 selector
   ```

## For EKS Deployment

If deploying on AWS EKS and want to use NLB LoadBalancer:

1. **Install AWS Load Balancer Controller:**
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName=<your-cluster-name>
   ```

2. **Gateway will automatically get an NLB IP:**
   ```bash
   kubectl get svc -n envoy-gateway-system
   # EXTERNAL-IP will show the NLB hostname/IP instead of <pending>
   ```

3. **Access via NLB:**
   ```bash
   NLB_IP=$(kubectl get svc envoy-devboard-devboard-gateway-bee4af0f -n envoy-gateway-system \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   echo "http://$NLB_IP/"
   ```
