#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "🚀 Starting ArgoCD installation with automated fixes..."

# 1. Fix the Kubernetes Node Taint (Single-node cluster fix)
echo ""
echo "🛠️  Checking and removing control-plane taints from nodes..."
# We use '|| true' because if the taint doesn't exist, the command will exit with 1.
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
echo "✅ Node taint removed (or was already removed)."

# 2. Download the Helm Chart Locally (Network Timeout Fix)
CHART_FILE="argo-cd.tgz"
CHART_VERSION="10.10.2"

echo ""
echo "📥 Downloading ArgoCD chart v${CHART_VERSION} locally to bypass Helm timeout..."
if [ ! -f "$CHART_FILE" ]; then
    curl -L "https://github.com/argoproj/argo-helm/releases/download/argo-cd-${CHART_VERSION}/argo-cd-${CHART_VERSION}.tgz" -o "$CHART_FILE"
    echo "✅ Download complete."
else
    echo "✅ Chart already exists locally, skipping download."
fi

# 3. Install via Helm using the local file
echo ""
echo "⚙️  Installing/Upgrading ArgoCD via Helm..."
helm upgrade -i argocd "./${CHART_FILE}" -n argocd --create-namespace -f gitops/argocd/install-values.yaml

echo ""
echo "🎉 ArgoCD installation successfully initiated!"
echo ""
echo "To get the admin password, run:"
echo 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo'
echo ""
echo "To port-forward the UI, run:"
echo "kubectl port-forward service/argocd-server -n argocd 8080:443"
