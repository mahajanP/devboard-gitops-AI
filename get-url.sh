#!/bin/bash
NODE_IP="172.25.232.68"
PORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=devboard -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}')
if [ -z "$PORT" ]; then
    echo "Error: Could not find the Envoy Gateway NodePort. Is the gateway running?"
else
    echo "Access the frontend at: http://${NODE_IP}:${PORT}/"
fi
