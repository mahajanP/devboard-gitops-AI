# PostgreSQL StatefulSet Pod Pending Issue - Fix Documentation

**Date:** October 9, 2026  
**Status:** ✅ RESOLVED  
**Issue:** postgres-statefulset-0 pod stuck in Pending state  
**Root Cause:** Storage class mismatch and unbound PersistentVolumeClaim (PVC)

---

## Problem Summary

The PostgreSQL StatefulSet pod was stuck in Pending state with error:
```
Warning  FailedScheduling  pod has unbound immediate PersistentVolumeClaims
```

---

## Root Cause

1. Storage Class Mismatch
   - StatefulSet requested storage class: manual
   - Available PV had storage class: manual
   - But StatefulSet volumeClaimTemplates had storage class: gp2 (not available)

2. PVC Could Not Bind
   - New PVC data-postgres-statefulset-0 remained Pending
   - No available PV with matching storage class

3. Pod Scheduling Failed
   - Without bound PVC, pod could not be scheduled

---

## Changes Made

### 1. Created gp2 StorageClass
\`\`\`bash
kubectl apply -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
\`\`\`

### 2. Created postgres-pv-gp2 PersistentVolume
\`\`\`bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv-gp2
  labels:
    app: devboard-postgres
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: gp2
  hostPath:
    path: /mnt/devboard-postgres
EOF
\`\`\`

### 3. Deleted Unbound PVCs
\`\`\`bash
kubectl delete pvc data-postgres-statefulset-0 -n devboard
kubectl delete pvc postgres-pvc -n devboard
\`\`\`

### 4. Recreated StatefulSet
\`\`\`bash
kubectl delete statefulset postgres-statefulset -n devboard --cascade=orphan
sleep 2
kubectl apply -f k8s/postgres-statefulset.yml -n devboard
\`\`\`

---

## Verification Steps

Step 1: Check StorageClass
\`\`\`bash
kubectl get storageclass gp2
\`\`\`

Step 2: Check PersistentVolume
\`\`\`bash
kubectl get pv postgres-pv-gp2
\`\`\`

Step 3: Check Pod Status (wait 10-30 seconds)
\`\`\`bash
sleep 10
kubectl get pod postgres-statefulset-0 -n devboard
# Expected: READY 1/1, STATUS Running
\`\`\`

Step 4: Check PVC Binding
\`\`\`bash
kubectl get pvc -n devboard
# Expected: data-postgres-statefulset-0 BOUND to postgres-pv-gp2
\`\`\`

Step 5: Check PostgreSQL Logs
\`\`\`bash
kubectl logs postgres-statefulset-0 -n devboard --tail=20
# Expected: database system is ready to accept connections
\`\`\`

---

## Result Summary

| Item | Before | After |
|------|--------|-------|
| Pod Status | Pending | ✅ Running |
| Pod Ready | 0/1 | ✅ 1/1 |
| PVC Status | Pending | ✅ Bound |
| StorageClass | Missing | ✅ Created |
| PostgreSQL | Not running | ✅ Ready |

---

## Rollback Instructions

\`\`\`bash
kubectl delete pv postgres-pv-gp2
kubectl delete storageclass gp2
kubectl delete statefulset postgres-statefulset -n devboard
kubectl apply -f k8s/Persistent-Volume.yml
kubectl apply -f k8s/persistent-volume-clame.yml
kubectl apply -f k8s/postgres-statefulset.yml -n devboard
\`\`\`

---

## Additional Fix - October 9, 2026

**Issue:** ArgoCD sync failed with: `StatefulSet.apps "postgres-statefulset" is invalid: spec: Forbidden: updates to statefulset spec for fields other than...`

**Root Cause:** The `volumeClaimTemplates` metadata in the manifest contained an invalid `namespace: devboard` field, which Kubernetes forbids because it's immutable after creation.

**Fix Applied:**
- Removed `namespace: devboard` from `volumeClaimTemplates.metadata`
- Kept `namespace: devboard` in the StatefulSet's `spec.metadata` (correct location)
- Deleted old StatefulSet with `--cascade=orphan` to preserve PVC data
- Reapplied corrected manifest from git
- Git commit: `8258f0b`

**Result (Verified October 9, 2026, 5:15 AM UTC):**
- ✅ ArgoCD sync: **Synced**
- ✅ Pod: **postgres-statefulset-0 running 1/1**
- ✅ PVC: **Bound to postgres-pv-gp2**
- ✅ No more immutable spec errors
- ✅ Backend API operational: `http://172.25.232.68:<NODE_PORT>/api/projects`
- ✅ Database queries working

See [gitops/TROUBLESHOOTING.md](gitops/TROUBLESHOOTING.md) for complete details.

---

## How to Find the Frontend/API Port
Since this is a local cluster using Envoy Gateway, the port is assigned dynamically. To find the current port to access the UI:
```bash
kubectl get svc -n envoy-gateway-system
# Look under PORT(S) for the 5-digit number (e.g., 80:31896/TCP)
```

---

## System Status Summary (October 9, 2026)

| Component | Status | Details |
|-----------|--------|---------|
| PostgreSQL Pod | ✅ Running 1/1 | postgres-statefulset-0 |
| PostgreSQL Data | ✅ Bound | data-postgres-statefulset-0 → postgres-pv-gp2 |
| ArgoCD Sync | ✅ Synced | All manifests in sync |
| Frontend | ✅ Running | Accessible at http://172.25.232.68:<NODE_PORT>/ |
| Backend API | ✅ Running | Responding with project data |
| AI Service | ✅ Running | Available at /api/ai endpoint |

---

Document Version: 1.3  
Last Updated: October 10, 2026  
Status: Complete ✅

---

## Additional Fix - October 10, 2026 (ArgoCD Sync Loop & Released PVs)

**Issue:** 
After deleting the `devboard` namespace to test ArgoCD deployment, Postgres got stuck in `Pending` again. 

**Root Cause:**
1. **ArgoCD Git Sync:** The local fix for `storageClassName: gp2` was not pushed to GitHub. Because ArgoCD pulls directly from Git (`selfHeal: true`), it overwrote the local fix and reapplied the old `manual` storage class.
2. **Released PV Lock:** When the namespace was deleted, the PVC was deleted, which caused the existing `postgres-pv` (manual) to enter a `Released` state. Kubernetes prevents a `Released` PV from binding to a new PVC until its `claimRef` is cleared.
3. **Double Claim:** There are TWO manifests asking for `manual` storage (`persistent-volume-clame.yml` and the StatefulSet `volumeClaimTemplates`), but only ONE `manual` PV existed.

**Fix Applied:**
1. **Unlocked Released PVs:** Patched the `postgres-pv` to clear the old claim so it became `Available` again:
   ```bash
   kubectl patch pv postgres-pv -p '{"spec":{"claimRef": null}}'
   ```
2. **Created a Second Manual PV:** Created a new PV (`postgres-pv-manual-2`) so both the standalone PVC and the StatefulSet PVC have a volume to bind to if ArgoCD forces the `manual` storage class again.
3. **Updated Automation Script:** Updated `fix-postgres.sh` to automatically unlock `Released` PVs and ensure a secondary manual PV exists.

**How to Prevent This Permanently:**
Ensure your GitHub repository has the correct `storageClassName: gp2` in `k8s/postgres-statefulset.yml`.
```bash
git add k8s/postgres-statefulset.yml
git commit -m "Update postgres storage class"
git push origin gitops
```
