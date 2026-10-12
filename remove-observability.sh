#!/usr/bin/env bash
# ==============================================================================
# Script: remove-observability.sh
# Purpose: Completely delete and clean up the Prometheus & Grafana Observability
#          stack, including Helm releases, namespaces, and background port-forwarding.
# ==============================================================================

set -euo pipefail

NAMESPACE="kube-prometheus-stack"
RELEASE_NAME="kube-prom-stack"
GRAFANA_PORT=8081

echo "=========================================================="
echo "       Removing Observability Stack (Prometheus & Grafana) "
echo "=========================================================="

# 1. Terminate any background port-forwarding for Grafana
echo "[1/4] Stopping background Grafana port-forwarding..."
pkill -f "port-forward.*${GRAFANA_PORT}:80" || true
pkill -f "port-forward.*kube-prom-stack-grafana" || true

# 2. Uninstall Helm release if present
echo "[2/4] Checking and uninstalling Helm release '${RELEASE_NAME}'..."
if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
    echo "Helm release '${RELEASE_NAME}' successfully uninstalled."
else
    echo "No active Helm release '${RELEASE_NAME}' found."
fi

# 3. Delete the observability namespace and all contained pods
echo "[3/4] Deleting namespace '${NAMESPACE}' and all associated pods..."
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete namespace "${NAMESPACE}" --timeout=60s || true
    echo "Namespace '${NAMESPACE}' removed."
else
    echo "Namespace '${NAMESPACE}' already does not exist."
fi

# 4. Final verification
echo "[4/4] Verifying removal..."
if kubectl get pods -A | grep -E "prom-|grafana|alertmanager|node-exporter" >/dev/null 2>&1; then
    echo "Warning: Some observability pods may still be terminating:"
    kubectl get pods -A | grep -E "prom-|grafana|alertmanager|node-exporter"
else
    echo "Verification passed: All observability pods and resources have been completely removed!"
fi

echo "=========================================================="
echo " Observability stack cleanup finished successfully!       "
echo "=========================================================="
