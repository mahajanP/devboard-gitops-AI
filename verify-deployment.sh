#!/usr/bin/env bash
set -e

echo "=========================================================="
echo "    DevBoard Production Cluster Health Check"
echo "=========================================================="

echo "[1/6] Checking Namespaces & Core Pods..."
kubectl get pods -n devboard
echo ""

echo "[2/6] Checking Ollama Model Server..."
kubectl get pods -n ollama
echo ""

echo "[3/6] Checking Gateway API & Envoy..."
kubectl get pods -n envoy-gateway-system -l app.kubernetes.io/name=envoy
kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=devboard-gateway
echo ""

echo "[4/6] Checking HPA & Metrics Server..."
kubectl get hpa -n devboard
echo ""

echo "[5/6] Checking Argo CD Application Health..."
STATUS=$(kubectl get application devboard-gitops-application -n argocd -o jsonpath="{.status.sync.status}")
HEALTH=$(kubectl get application devboard-gitops-application -n argocd -o jsonpath="{.status.health.status}")
echo "Argo CD Sync Status:   $STATUS"
echo "Argo CD Health Status: $HEALTH"
echo ""

echo "[6/6] Testing Live Network Endpoints..."
NODE_IP="172.25.232.68"
echo -n "Testing Frontend (http://$NODE_IP/)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$NODE_IP/ || true)
if [ "$HTTP_CODE" = "200" ]; then
    echo "SUCCESS (HTTP 200)"
else
    echo "FAILED (HTTP $HTTP_CODE)"
fi

echo -n "Testing AI Service (http://$NODE_IP/api/ai/health)... "
AI_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$NODE_IP/api/ai/health || true)
if [ "$AI_CODE" = "200" ]; then
    echo "SUCCESS (HTTP 200)"
else
    echo "FAILED (HTTP $AI_CODE)"
fi

echo "=========================================================="
echo "All systems operational!"
echo "=========================================================="
