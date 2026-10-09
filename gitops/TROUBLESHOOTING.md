# Troubleshooting Guide

## ArgoCD Sync Errors

### StatefulSet "postgres-statefulset" is invalid: spec: Forbidden

**Error message:**
```
StatefulSet.apps "postgres-statefulset" is invalid: spec: Forbidden: 
updates to statefulset spec for fields other than 'replicas', 'ordinals', 
'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 
'minReadySeconds' are forbidden
```

**Root Cause:**
Kubernetes prevents updates to immutable StatefulSet fields after creation. Valid fields that can be modified are:
- `replicas`
- `ordinals`
- `template`
- `updateStrategy`
- `persistentVolumeClaimRetentionPolicy`
- `minReadySeconds`

**For postgres-statefulset specifically:**
The `volumeClaimTemplates` metadata should NOT include a `namespace` field. This field is inherited from the parent StatefulSet and becomes immutable once created.

**The Fix Applied (October 9, 2026):**

The invalid namespace field was removed from `volumeClaimTemplates` in the postgres-statefulset manifest:

❌ **Was Incorrect:**
```yaml
volumeClaimTemplates:
  - metadata:
      name: data
      namespace: devboard    # ← INVALID - causes immutable spec error
    spec:
      storageClassName: manual
      ...
```

✅ **Now Correct:**
```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      storageClassName: manual
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
```

**Changes Made:**
1. Removed `namespace: devboard` from volumeClaimTemplates metadata
2. Kept `namespace: devboard` in StatefulSet spec.metadata (correct location)
3. Commit: `8258f0b` — "fix: remove namespace from postgres volumeClaimTemplates metadata - fixes immutable spec error"
4. Deleted old StatefulSet with `--cascade=orphan` to preserve PVCs
5. Reapplied corrected manifest

**Verification:**
```bash
# Check StatefulSet is running
kubectl get statefulset postgres-statefulset -n devboard
# Expected: Ready 1/1

# Check pod is running  
kubectl get pod postgres-statefulset-0 -n devboard
# Expected: READY 1/1, STATUS Running

# Verify ArgoCD sync succeeded
kubectl get application devboard-gitops-application -n argocd -o wide
# Expected: SYNC STATUS Synced
```

**If Already Deployed with Incorrect Config:**

1. Delete the StatefulSet (keep pods/PVCs):
   ```bash
   kubectl delete statefulset postgres-statefulset -n devboard --cascade=orphan
   ```

2. Apply the corrected manifest:
   ```bash
   kubectl apply -f k8s/postgres-statefulset.yml -n devboard
   ```

3. Verify postgres pod recovers:
   ```bash
   kubectl get pod postgres-statefulset-0 -n devboard -w
   ```

4. Ensure changes are pushed to git:
   ```bash
   cd /devboard-gitops/devboard
   git commit -am "fix: remove namespace from postgres-statefulset volumeClaimTemplates"
   git push origin gitops
   ```

5. Trigger ArgoCD sync (happens automatically with selfHeal enabled):
   ```bash
   kubectl patch application devboard-gitops-application -n argocd -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

---

## Gateway & Access Issues

### Application inaccessible on expected port

**Symptom:** Gateway shows ADDRESS as `<pending>` or not accessible via LoadBalancer IP

**Root Cause:** 
- LoadBalancer service waiting for external IP assignment  
- Local/non-cloud environments use NodePort instead
- See [APPLICATION_ACCESS.md](APPLICATION_ACCESS.md) for current access method  

**Solution:**
Use NodePort (automatically created as fallback):
```bash
# Get the NodePort
kubectl get svc -n envoy-gateway-system | grep envoy-devboard
# Look for PORT(S) column, e.g., 80:31385/TCP

# Access via NodePort
http://172.25.232.68:31385/
```

For EKS/cloud deployments, install AWS Load Balancer Controller to get auto-provisioned NLB IP.

---

## Other Common Issues

### PVC Remains Pending
See [POSTGRES_FIX_DOCUMENTATION.md](../POSTGRES_FIX_DOCUMENTATION.md) for storage class and PV troubleshooting.

### HPA Shows "Degraded" with Failed Metrics
**Cause:** Metrics server not installed in cluster  
**Status:** This is not a postgres issue, it's an infrastructure issue  
**Fix:** Install metrics-server for CPU-based autoscaling
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Quick Reference

| Issue | Command | Expected Output |
|-------|---------|-----------------|
| Check application sync status | `kubectl get application devboard-gitops-application -n argocd -o wide` | `Synced` |
| Check postgres pod | `kubectl get pod postgres-statefulset-0 -n devboard` | `Running 1/1` |
| Check postgres PVC | `kubectl get pvc -n devboard \| grep postgres` | `Bound` |
| Check statefulset | `kubectl get statefulset postgres-statefulset -n devboard` | `Ready 1/1` |
| Check git branch | `cd /devboard-gitops/devboard && git log --oneline -1` | Latest commit hash |
| Inspect manifest | `kubectl get statefulset postgres-statefulset -n devboard -o yaml \| grep -A 10 volumeClaimTemplates` | No `namespace:` field in metadata |
