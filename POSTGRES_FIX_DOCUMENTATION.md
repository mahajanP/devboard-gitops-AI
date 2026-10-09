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

Document Version: 1.0  
Last Updated: October 9, 2026  
Status: Complete ✅
