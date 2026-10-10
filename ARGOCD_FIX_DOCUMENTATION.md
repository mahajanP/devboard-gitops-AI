# ArgoCD Installation Fixes

This document details the issues encountered while trying to install ArgoCD via Helm and the exact steps taken to resolve them.

## Issue 1: Network Timeout Downloading Helm Chart

**The Problem:**
When running the standard `helm install` command, the installation timed out with the following error:
\`\`\`text
Error: INSTALLATION FAILED: Get "https://release-assets.githubusercontent.com/...": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
\`\`\`
The server's network was either blocking or heavily rate-limiting traffic to GitHub's release asset IP addresses (`185.199.109.133`).

**The Fix:**
Instead of relying on Helm to stream the chart directly from GitHub (which times out after a short period), the chart was manually downloaded using `curl` and then installed from the local file.

**Commands executed:**
\`\`\`bash
# 1. Download the chart manually (takes a few minutes due to slow routing)
curl -v -L "https://github.com/argoproj/argo-helm/releases/download/argo-cd-10.10.2/argo-cd-10.10.2.tgz" -o argo-cd.tgz

# 2. Run helm install using the local tarball
helm upgrade -i argocd ./argo-cd.tgz -n argocd --create-namespace -f gitops/argocd/install-values.yaml
\`\`\`

---

## Issue 2: ArgoCD Pods Stuck in "Pending" State

**The Problem:**
After the chart was successfully passed to Kubernetes, the `helm install` command hung again. Checking the pods revealed that the ArgoCD pre-upgrade hook (`argocd-redis-secret-init`) was stuck in a `Pending` state.

Describing the pod showed the following scheduling error:
\`\`\`text
0/1 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }.
\`\`\`
Because the cluster is a single-node setup, Kubernetes applied a default security taint (`NoSchedule`) to the master/control-plane node to prevent regular application pods from running on it.

**The Fix:**
The restrictive taint was removed from the control-plane node, allowing ArgoCD (and any future workloads) to be scheduled and run on the node.

**Commands executed:**
\`\`\`bash
# 1. Remove the control-plane taint from all nodes
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 2. Verify pods are transitioning to ContainerCreating / Running
kubectl get pods -n argocd
\`\`\`

After removing the taint, the pods successfully spun up and the Helm installation completed successfully!

---

## Troubleshooting FAQ: What if ArgoCD Fails or is Deleted?

### Issue: Deleting the ArgoCD Application does not delete the DevBoard resources
When you delete an ArgoCD `Application` (e.g., via `kubectl delete -f devboard-application.yml`), ArgoCD only deletes the "manager" configuration. It leaves the actual Kubernetes resources (Deployments, Pods, Services) running in the cluster.

**The Fix:**
To make ArgoCD automatically clean up the project when the application is deleted (Cascade Deletion), a **Finalizer** must be added to the application manifest. This has now been added to `gitops/argocd/devboard-application.yml`:
```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```
*(If you need to manually clean up orphaned resources, simply run: `kubectl delete namespace devboard`)*

### Issue: How to troubleshoot the application if ArgoCD is down?
ArgoCD is only the **manager**. Kubernetes is the **engine** that runs your application. If ArgoCD crashes, is deleted, or goes offline, your frontend, backend, and database will **continue running completely unaffected**.

If ArgoCD is unavailable and you need to troubleshoot your application, bypass ArgoCD and use native Kubernetes commands:

**1. Check application health:**
```bash
kubectl get pods -n devboard
```

**2. Check application logs:**
```bash
# Replace with the actual pod name
kubectl logs pod/devboard-backend-deployment-xxxxx -n devboard
```

**3. Check application errors / events:**
```bash
kubectl describe pod/devboard-backend-deployment-xxxxx -n devboard
```

### Issue: How to fix ArgoCD itself?
If your application is fine but ArgoCD is stuck or failing to sync:

**1. Check ArgoCD components:**
```bash
kubectl get pods -n argocd
```

**2. Check ArgoCD server logs:**
```bash
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd
```

**3. Restart ArgoCD (Safe to do, will not affect the running DevBoard app):**
```bash
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
```
