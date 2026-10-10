# How to Access the DevBoard Frontend

The DevBoard application is exposed via an Envoy Gateway LoadBalancer service. In a local Kubernetes cluster without a cloud LoadBalancer provider, the service is assigned a **dynamic NodePort** (a port in the 30000-32767 range) each time it is created or recreated. 

If you are unable to access the frontend, it is likely because the NodePort is different from the one you are trying to use.

## Step-by-Step: How to Check the Port

1. **Find the Envoy Gateway Service Port**
   Run the following command to see all services in the `envoy-gateway-system` namespace:
   ```bash
   kubectl get svc -n envoy-gateway-system
   ```

2. **Locate the Port Number**
   Look for the service named `envoy-devboard-devboard-gateway-...` (Type: `LoadBalancer`).
   Under the `PORT(S)` column, you will see something like `80:31896/TCP`.
   The 5-digit number after the colon (e.g., **31896**) is your current NodePort.

3. **Construct the URL**
   Combine your node IP (`172.25.232.68`) with the NodePort you found.
   **Current URL:** `http://172.25.232.68:31896/` (Since the user was trying `31385`, this is why it was failing).

---

## One-liner command to get the exact URL
You can run this command anytime to generate the correct URL automatically:

```bash
echo "http://172.25.232.68:$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=devboard -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}')/"
```

## Creating a Helper Script

You can create a quick helper script to do this for you:

1. Create a file named `get-url.sh`:
   ```bash
   cat << 'EOF' > get-url.sh
   #!/bin/bash
   NODE_IP="172.25.232.68"
   PORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=devboard -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}')
   if [ -z "$PORT" ]; then
       echo "Error: Could not find the Envoy Gateway NodePort."
   else
       echo "Access the frontend at: http://${NODE_IP}:${PORT}/"
   fi
   EOF
   ```
2. Make it executable:
   ```bash
   chmod +x get-url.sh
   ```
3. Run it whenever you need the URL:
   ```bash
   ./get-url.sh
   ```
