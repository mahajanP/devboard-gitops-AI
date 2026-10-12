# Devboard Kubernetes Troubleshooting Documentation

This document summarizes the issues encountered and resolved in the local Kubernetes cluster (WSL/containerd) for the Devboard application, including Postgres, the AI Service, and the Envoy Gateway frontend routing.

## 1. Postgres Database Stuck in `Pending` State
**Symptoms:**
- The Postgres Pod was stuck in a `Pending` state.
- The PersistentVolumeClaim (PVC) was waiting for a volume to be created, but no matching PersistentVolume (PV) was available or the existing PVs were in a `Released` state and could not be bound.
- The original PVC did not specify a `storageClassName`, breaking dynamic provisioning in the local cluster.

**Root Cause:**
When a namespace is deleted, PVs with a `Retain` reclaim policy enter a `Released` state. In Kubernetes, a `Released` PV cannot be claimed by a new PVC until its `claimRef` is cleared.

**Resolution:**
1. **Patched the `Released` PVs:** Cleared the `spec.claimRef` of the existing `postgres-pv-manual` to make it `Available` again.
2. **Updated the YAML:** Ensured that the PVC requests `storageClassName: gp2` (which was set as the default/available storage class).
3. **Created a Fix Script:** Added `fix-postgres.sh` to automate patching the PV and creating a secondary manual PV (`postgres-pv-manual-2`) as a fallback.
4. **GitOps Note:** *Crucial Step* - The user must push the `storageClassName: gp2` fix to their GitHub repository, otherwise ArgoCD's `selfHeal` feature will overwrite the local changes and break Postgres again.

---

## 2. AI Service Failing with `[Errno -2] Name or service not known`
**Symptoms:**
- The AI Service backend was throwing DNS errors: `[Errno -2] Name or service not known` when trying to contact Ollama.
- Ollama was either not running or not deployed correctly in the cluster.

**Root Cause:**
The `ai-service` was trying to resolve `ollama.ollama.svc.cluster.local`, but the Ollama deployment/service was missing or unreachable in the `ollama` namespace. 

**Resolution:**
1. **Deployed Native Ollama:** Deployed the official `ollama/ollama:latest` image directly to the Kubernetes cluster.
2. **Preserved Models via HostPath:** Because downloading the `llama3.2:1b` model takes a long time and network speeds were slow, we used a `HostPath` volume (`/tmp/ollama-models`) mapped to `/root/.ollama` inside the container. This caches the model locally on the host, preventing the need to re-download it if the pod restarts.
3. **Verified Connection:** Executed requests inside the cluster from the `ai-service` to the `ollama` service, confirming that text streaming works successfully.

---

## 3. UI Throwing `NetworkError` and Envoy Gateway `<pending>`
**Symptoms:**
- The AI Assistant UI in the browser failed to connect with a `NetworkError`.
- Trying to access the UI via `http://localhost:3005/` resulted in "Not Found".
- The `envoy-devboard-devboard-gateway-...` Service of type `LoadBalancer` was stuck in a `<pending>` state.
- The `envoy-devboard-devboard-gateway-...` Pod was `1/2` Ready, failing its readiness probe with `HTTP 503`.

**Root Cause:**
1. **LoadBalancer Pending:** In a local bare-metal Kubernetes cluster (without a cloud provider or MetalLB), `LoadBalancer` services will stay `<pending>` indefinitely because there is no external IP to assign. This is normal. Kubernetes falls back to assigning a **NodePort** (in this case, `32395`).
2. **Proxy Pod Disconnected:** The Envoy proxy pod had disconnected from its control plane (`envoy-gateway-system` controller) hours prior and got stuck with a "Connection refused" error to the xDS configuration stream. Because it lacked valid configuration, it marked itself as unhealthy and returned 503s on its health check, dropping all traffic.

**Resolution:**
1. **Restarted the Proxy Pod:** Deleted the stuck Envoy proxy pod (`kubectl delete pod envoy-devboard... -n envoy-gateway-system`). The newly spun-up pod instantly connected to the control plane, grabbed the HTTPRoute configurations, and became `2/2` Ready.
2. **Fixed the `<pending>` LoadBalancer IP:**
   - In bare-metal environments without a cloud provider or MetalLB, LoadBalancer services remain `<pending>`.
   - We resolved this by patching the Service status and assigning the host/node IP `172.25.232.68` as both the LoadBalancer Ingress IP and an `externalIP`:
     ```bash
     kubectl patch svc envoy-devboard-devboard-gateway-bee4af0f -n envoy-gateway-system --subresource=status -p '{"status":{"loadBalancer":{"ingress":[{"ip":"172.25.232.68"}]}}}'
     kubectl patch svc envoy-devboard-devboard-gateway-bee4af0f -n envoy-gateway-system -p '{"spec":{"externalIPs":["172.25.232.68"]}}'
     ```
   - This transitioned the Gateway resource to `Programmed: True` with `Address assigned to the Gateway`.
   - The Service now shows `EXTERNAL-IP: 172.25.232.68` (no longer `<pending>`).
3. **Verified Access:** 
   - You can now access the app directly on standard port 80: `http://172.25.232.68/`
   - It also remains accessible via the NodePort: `http://172.25.232.68:32395/`
   - Both the Frontend and AI Backend (`/api/ai/health`) return HTTP 200.

---

## 4. Prometheus Node Exporter Stuck in `CreateContainerError`
**Symptoms:**
- Pod `kube-prom-stack-prometheus-node-exporter-...` in `kube-prometheus-stack` was stuck in `CreateContainerError`.
- Kubelet event message:
  ```text
  Error: failed to generate container spec: failed to generate spec: path "/" is mounted on "/" but it is not a shared or slave mount
  ```

**Root Cause:**
In WSL 2 / bare-metal environments, the host root filesystem (`/`) is mounted with `private` propagation by default. The Prometheus Node Exporter DaemonSet had `mountPropagation: HostToContainer` on the `/host/root` volume mount. Kubernetes and containerd require the host mount to be `rshared` or `rslave` when `HostToContainer` propagation is requested, failing container creation.

**Resolution:**
Patched the DaemonSet to change `mountPropagation` on `/host/root` to `None`:
```bash
kubectl patch ds kube-prom-stack-prometheus-node-exporter -n kube-prometheus-stack --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/volumeMounts/2/mountPropagation","value":"None"}]'
```
The node-exporter pod immediately launched and reached `1/1 Running`, successfully exporting host metrics on port `9100`.

---

## 5. Grafana Port-Forward `Error from server (NotFound): services not found`
**Symptoms:**
- Running `kubectl port-forward svc/kube-prom-stack-grafana 8081:80` fails with:
  ```text
  Error from server (NotFound): services "kube-prom-stack-grafana" not found
  ```

**Root Cause:**
`kubectl` defaults to searching within the `default` namespace when no `-n` namespace flag is specified. The Prometheus and Grafana components were installed in the custom namespace `kube-prometheus-stack`.

**Resolution:**
Specify the namespace explicitly in the port-forward command:
```bash
kubectl port-forward svc/kube-prom-stack-grafana -n kube-prometheus-stack 8081:80 --address 0.0.0.0 &
```

**Credentials Retrieval:**
- **URL:** `http://localhost:8081/` (or `http://172.25.232.68:8081/`)
- **Username:** `admin`
- **Password Command:**
  ```bash
  kubectl get secret -n kube-prometheus-stack kube-prom-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
  ```
