# ArgoCD Installation Fixes

This document details the issues encountered while trying to install ArgoCD via Helm and the exact steps taken to resolve them.

## Issue 1: Network Timeout Downloading Helm Chart

**The Problem:**
When running the standard `helm install` command, the installation timed out with the following error:
\`\`\`text
Error: INSTALLATION FAILED: Get "https://release-assets.githubusercontent.com/...": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
\`\`\`
The server's network was either blocking or heavily rate-limiting traffic to GitHub's release asset IP addresses (`185.199.109.133`).

**The Fix:**
Instead of relying on Helm to stream the chart directly from GitHub (which times out after a short period), the chart was manually downloaded using `curl` and then installed from the local file.

**Commands executed:**
\`\`\`bash
# 1. Download the chart manually (takes a few minutes due to slow routing)
curl -v -L "https://github.com/argoproj/argo-helm/releases/download/argo-cd-10.10.2/argo-cd-10.10.2.tgz" -o argo-cd.tgz

# 2. Run helm install using the local tarball
helm upgrade -i argocd ./argo-cd.tgz -n argocd --create-namespace -f gitops/argocd/install-values.yaml
\`\`\`

---

## Issue 2: ArgoCD Pods Stuck in "Pending" State

**The Problem:**
After the chart was successfully passed to Kubernetes, the `helm install` command hung again. Checking the pods revealed that the ArgoCD pre-upgrade hook (`argocd-redis-secret-init`) was stuck in a `Pending` state.

Describing the pod showed the following scheduling error:
\`\`\`text
0/1 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }.
\`\`\`
Because the cluster is a single-node setup, Kubernetes applied a default security taint (`NoSchedule`) to the master/control-plane node to prevent regular application pods from running on it.

**The Fix:**
The restrictive taint was removed from the control-plane node, allowing ArgoCD (and any future workloads) to be scheduled and run on the node.

**Commands executed:**
\`\`\`bash
# 1. Remove the control-plane taint from all nodes
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 2. Verify pods are transitioning to ContainerCreating / Running
kubectl get pods -n argocd
\`\`\`

After removing the taint, the pods successfully spun up and the Helm installation completed successfully!
