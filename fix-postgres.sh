#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "🚀 Starting PostgreSQL StatefulSet automated fix..."

echo ""
echo "🛠️  Step 1: Creating 'gp2' StorageClass..."
cat << 'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

echo ""
echo "🛠️  Step 2: Creating 'postgres-pv-gp2' PersistentVolume..."
cat << 'EOF' | kubectl apply -f -
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

echo ""
echo "🧹 Step 3: Deleting unbound PersistentVolumeClaims (PVCs)..."
kubectl delete pvc data-postgres-statefulset-0 -n devboard --ignore-not-found
kubectl delete pvc postgres-pvc -n devboard --ignore-not-found

echo ""
echo "🧹 Step 4: Deleting old StatefulSet (preserving data with cascade=orphan)..."
kubectl delete statefulset postgres-statefulset -n devboard --cascade=orphan --ignore-not-found

# Wait for deletion to complete (Kubernetes API is asynchronous)
echo "⏳ Waiting for StatefulSet to be fully deleted..."
while kubectl get statefulset postgres-statefulset -n devboard 2>/dev/null; do 
  sleep 2
done

echo ""
echo "🔄 Step 5: Recreating the StatefulSet..."
kubectl apply -f k8s/postgres-statefulset.yml -n devboard

echo ""
echo "⏳ Waiting for the new Postgres pod to become Ready..."
# Wait for the pod to be created
sleep 5
kubectl wait --for=condition=Ready pod/postgres-statefulset-0 -n devboard --timeout=120s

echo ""
echo "🔄 Step 6: Restarting backend pod to restore database connection..."
kubectl delete pod -n devboard -l app=devboard-backend

echo ""
echo "🎉 PostgreSQL fix completed successfully! Everything is back online."
