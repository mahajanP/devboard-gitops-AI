#!/usr/bin/env bash
# ==============================================================================
# Script: observability.sh
# Purpose: Deploy and test the Prometheus & Grafana Observability stack
# Usage:
#   ./observability.sh deploy  - Installs kube-prometheus-stack, patches node-exporter, and sets up port-forwarding
#   ./observability.sh test    - Tests Prometheus, Grafana, and Node Exporter endpoints
#   ./observability.sh clean   - Removes the observability stack and cleans up resources
#   ./observability.sh         - Runs full cycle (deploy -> test)
# ==============================================================================

set -euo pipefail

NAMESPACE="kube-prometheus-stack"
RELEASE_NAME="kube-prom-stack"
GRAFANA_PORT=8081

deploy_stack() {
    echo "=========================================================="
    echo "       [1/4] Installing Prometheus & Grafana Stack        "
    echo "=========================================================="

    if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        echo "Release '${RELEASE_NAME}' already exists. Upgrading..."
        helm upgrade "${RELEASE_NAME}" oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
            --namespace "${NAMESPACE}"
    else
        echo "Installing '${RELEASE_NAME}' in namespace '${NAMESPACE}'..."
        helm install "${RELEASE_NAME}" oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
            --namespace "${NAMESPACE}" \
            --create-namespace
    fi

    echo ""
    echo "=========================================================="
    echo "       [2/4] Patching Node-Exporter for WSL/Bare-Metal   "
    echo "=========================================================="
    echo "Waiting for node-exporter DaemonSet to be available..."
    until kubectl get ds "${RELEASE_NAME}-prometheus-node-exporter" -n "${NAMESPACE}" >/dev/null 2>&1; do
        sleep 2
    done

    # Fix WSL private root mount issue: change mountPropagation from HostToContainer to None
    echo "Patching node-exporter mountPropagation to prevent CreateContainerError..."
    kubectl patch ds "${RELEASE_NAME}-prometheus-node-exporter" -n "${NAMESPACE}" \
        --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/volumeMounts/2/mountPropagation","value":"None"}]' || true

    echo ""
    echo "=========================================================="
    echo "       [3/4] Waiting for Observability Pods to be Ready   "
    echo "=========================================================="
    echo "Waiting for Grafana deployment..."
    kubectl rollout status deployment/"${RELEASE_NAME}-grafana" -n "${NAMESPACE}" --timeout=180s

    echo "Waiting for Prometheus operator..."
    kubectl rollout status deployment/"${RELEASE_NAME}-kube-prome-operator" -n "${NAMESPACE}" --timeout=180s

    echo "Waiting for Node Exporter daemonset..."
    kubectl rollout status daemonset/"${RELEASE_NAME}-prometheus-node-exporter" -n "${NAMESPACE}" --timeout=180s

    echo ""
    echo "=========================================================="
    echo "       [4/4] Starting Grafana Port-Forwarding            "
    echo "=========================================================="
    # Kill any existing port-forward on port 8081
    pkill -f "port-forward.*${GRAFANA_PORT}:80" || true

    echo "Starting background port-forward on port ${GRAFANA_PORT}..."
    kubectl port-forward svc/"${RELEASE_NAME}-grafana" -n "${NAMESPACE}" "${GRAFANA_PORT}:80" --address 0.0.0.0 >/dev/null 2>&1 &
    sleep 3

    echo ""
    echo "Retrieving Grafana admin password..."
    GRAFANA_PW=$(kubectl get secret -n "${NAMESPACE}" "${RELEASE_NAME}-grafana" -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo "admin")
    echo "----------------------------------------------------------"
    echo " Grafana URL:      http://localhost:${GRAFANA_PORT}/ (or http://172.25.232.68:${GRAFANA_PORT}/)"
    echo " Grafana Username: admin"
    echo " Grafana Password: ${GRAFANA_PW}"
    echo "----------------------------------------------------------"
}

test_stack() {
    echo ""
    echo "=========================================================="
    echo "          Testing Observability Endpoints                 "
    echo "=========================================================="

    # 1. Test Grafana Port-Forward
    echo -n "Testing Grafana Web UI (http://localhost:${GRAFANA_PORT}/)... "
    G_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${GRAFANA_PORT}/" || true)
    if [ "${G_CODE}" = "200" ] || [ "${G_CODE}" = "302" ]; then
        echo "SUCCESS (HTTP ${G_CODE})"
    else
        echo "FAILED (HTTP ${G_CODE})"
    fi

    # 2. Test Node Exporter Host Metrics
    echo -n "Testing Node Exporter Metrics (http://localhost:9100/metrics)... "
    NE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9100/metrics" || true)
    if [ "${NE_CODE}" = "200" ]; then
        echo "SUCCESS (HTTP ${NE_CODE})"
    else
        echo "FAILED (HTTP ${NE_CODE})"
    fi

    echo ""
    echo "Listing all running Observability pods:"
    kubectl get pods -n "${NAMESPACE}"
}

clean_stack() {
    echo ""
    echo "=========================================================="
    echo "       Cleaning up Observability Stack                    "
    echo "=========================================================="
    
    echo "Stopping Grafana port-forward..."
    pkill -f "port-forward.*${GRAFANA_PORT}:80" || true

    echo "Uninstalling Helm release '${RELEASE_NAME}'..."
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}" || true

    echo "Deleting namespace '${NAMESPACE}'..."
    kubectl delete namespace "${NAMESPACE}" --timeout=60s || true

    echo "Observability stack successfully removed!"
}

# Main command dispatcher
ACTION="${1:-all}"

case "${ACTION}" in
    deploy)
        deploy_stack
        ;;
    test)
        test_stack
        ;;
    clean|remove)
        clean_stack
        ;;
    all)
        deploy_stack
        test_stack
        ;;
    *)
        echo "Usage: $0 {deploy|test|clean|all}"
        exit 1
        ;;
esac
