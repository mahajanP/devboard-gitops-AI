#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "🚀 Starting Comprehensive PostgreSQL Automated Fix..."

echo ""
echo "🔓 Step 1: Unlocking any 'Released' Persistent Volumes (PVs)..."
# When a PVC is deleted, the PV goes into "Released" state and cannot be reused.
# This clears the claimRef so it becomes "Available" again.
RELEASED_PVS=$(kubectl get pv | grep Released | awk '{print $1}' || true)
if [ ! -z "$RELEASED_PVS" ]; then
    for pv in $RELEASED_PVS; do
        echo "   -> Patching $pv to make it Available again..."
        kubectl patch pv $pv -p '{"spec":{"claimRef": null}}'
    done
else
    echo "   -> No Released PVs found."
fi

echo ""
echo "🛠️  Step 2: Ensuring enough 'manual' Storage is available..."
# Because there are TWO claims that might ask for 'manual' (postgres-pvc and data-postgres-statefulset-0)
# we need to make sure a second 'manual' PV exists.
cat << 'INNER_EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv-manual-2
  labels:
    app: devboard-postgres
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  hostPath:
    path: /mnt/devboard-postgres-2
INNER_EOF

echo ""
echo "🛠️  Step 3: Ensuring 'gp2' StorageClass and PV exist (Future-proofing)..."
cat << 'INNER_EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
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
INNER_EOF

echo ""
echo "🧹 Step 4: Deleting stuck PVCs..."
kubectl delete pvc data-postgres-statefulset-0 -n devboard --ignore-not-found
kubectl delete pvc postgres-pvc -n devboard --ignore-not-found

echo ""
echo "🧹 Step 5: Deleting old StatefulSet (preserving data with cascade=orphan)..."
kubectl delete statefulset postgres-statefulset -n devboard --cascade=orphan --ignore-not-found

echo "⏳ Waiting for StatefulSet to be fully deleted..."
while kubectl get statefulset postgres-statefulset -n devboard 2>/dev/null; do 
  sleep 2
done

echo ""
echo "🔄 Step 6: Triggering ArgoCD/Kubernetes to Recreate the StatefulSet..."
# We apply the local one just in case ArgoCD is not running. If ArgoCD is running, it will self-heal anyway.
kubectl apply -f k8s/postgres-statefulset.yml -n devboard

echo ""
echo "⏳ Waiting for the new Postgres pod to become Ready..."
sleep 5
kubectl wait --for=condition=Ready pod/postgres-statefulset-0 -n devboard --timeout=120s

echo ""
echo "🔄 Step 7: Restarting backend pod to restore database connection..."
kubectl delete pod -n devboard -l app=devboard-backend

echo ""
echo "🎉 PostgreSQL fix completed successfully! Everything is back online."
