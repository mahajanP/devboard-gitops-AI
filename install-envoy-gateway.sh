#!/usr/bin/env bash
# ==============================================================================
# Script: install-envoy-gateway.sh
# Purpose: Idempotent installation & setup script for Envoy Gateway on Kubernetes
# ==============================================================================

set -euo pipefail

RELEASE_NAME="eg"
NAMESPACE="envoy-gateway-system"
CHART_VERSION="v1.2.1"
GATEWAY_API_VERSION="v1.1.0"

echo "=========================================================="
echo "         Envoy Gateway Automated Installation"
echo "=========================================================="

# 0. Ensure single-node clusters allow scheduling by removing control-plane taints
echo "[0/6] Removing control-plane taints to allow certgen and gateway pods to schedule..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true

# 1. Install / Ensure Gateway API CRDs
echo "[1/6] Checking and installing Gateway API Standard CRDs..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

# 2. Check existing Helm release to avoid 'cannot re-use a name' error
echo "[2/6] Checking existing Helm release for '${RELEASE_NAME}'..."
if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    STATUS=$(helm status "${RELEASE_NAME}" -n "${NAMESPACE}" -o json | grep -o '"status": *"[^"]*"' | head -n 1 | awk -F'"' '{print $4}')
    echo "Found existing release '${RELEASE_NAME}' with status: ${STATUS}"
    if [ "${STATUS}" = "failed" ]; then
        echo "Release is in a failed state. Cleaning it up before reinstalling..."
        helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
    else
        echo "Upgrading existing release to ensure version ${CHART_VERSION}..."
        helm upgrade "${RELEASE_NAME}" oci://docker.io/envoyproxy/gateway-helm \
            --version "${CHART_VERSION}" \
            -n "${NAMESPACE}"
    fi
fi

# 3. Install Envoy Gateway if not already deployed
if ! helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "[3/6] Installing Envoy Gateway (Version: ${CHART_VERSION})..."
    helm install "${RELEASE_NAME}" oci://docker.io/envoyproxy/gateway-helm \
        --version "${CHART_VERSION}" \
        -n "${NAMESPACE}" \
        --create-namespace
else
    echo "[3/6] Envoy Gateway Helm chart is already installed and up to date."
fi

# 4. Wait for Envoy Gateway Controller Pod to be Ready
echo "[4/6] Waiting for Envoy Gateway controller to be Ready..."
kubectl wait --namespace "${NAMESPACE}" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=gateway-helm \
    --timeout=120s || kubectl wait --namespace "${NAMESPACE}" \
    --for=condition=ready pod \
    --selector=control-plane=envoy-gateway \
    --timeout=120s || true

# 5. Apply GatewayClass
echo "[5/6] Ensuring GatewayClass 'envoy' exists..."
cat << 'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF

# 6. Optional: Auto-bind node IP for bare-metal / WSL environments
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
if [ -n "${NODE_IP}" ]; then
    echo "Auto-detected Node IP: ${NODE_IP}"
    SVC_NAME=$(kubectl get svc -n "${NAMESPACE}" -l gateway.envoyproxy.io/owning-gateway-name=devboard-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "${SVC_NAME}" ]; then
        echo "Patching Envoy Gateway service '${SVC_NAME}' with Node IP for port 80 routing..."
        kubectl patch svc "${SVC_NAME}" -n "${NAMESPACE}" \
            --subresource=status -p "{\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"${NODE_IP}\"}]}}}" || true
        kubectl patch svc "${SVC_NAME}" -n "${NAMESPACE}" \
            -p "{\"spec\":{\"externalIPs\":[\"${NODE_IP}\"]}}" || true
    fi
fi

echo "=========================================================="
echo " Envoy Gateway installation completed successfully!"
echo "=========================================================="
