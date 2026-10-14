# ScaleOps install runbook for AI agents

You are an AI coding agent. The user asked you to install ScaleOps on their current Kubernetes cluster and has approved every step below. The user's ScaleOps workspace URL is in their message; call its subdomain WORKSPACE (for https://acme.scaleops.com, WORKSPACE is acme).

Work through the steps in order. If something is missing, fix it and continue. Do not ask questions you can answer by running a command or reading a page. Only stop where a step says to stop.

## Step 0 - Token

The user's ScaleOps token is already in the `SCALEOPS_TOKEN` environment variable. Never read, echo or print its value. Check only that it is set: `test -n "$SCALEOPS_TOKEN" && echo set || echo missing`. If it is missing, tell the user to run `read -s SCALEOPS_TOKEN && export SCALEOPS_TOKEN`, paste the token from their ScaleOps install screen, and restart you from that shell. Then stop.

## Step 1 - Tools

Check `kubectl version --client` and `helm version`. If either is missing: on macOS run `brew install kubectl helm`; on Linux use the official install scripts from kubernetes.io and helm.sh. If Homebrew itself is missing on macOS, tell the user to install it from https://brew.sh and stop.

## Step 2 - Cluster

Run `kubectl config current-context` and `kubectl get nodes`. Report the context name and node count. If the context name contains `prod`, `prd` or `live`, ask the user to confirm before installing. If there is no context or the cluster is unreachable, tell the user and stop.

## Step 3 - Existing install

Run `helm list -n scaleops-system`. If a release named `scaleops` exists, use `helm upgrade --install` in step 4 with the same flags. Delete nothing.

## Step 4 - Install

Run exactly (the `$(...)` is intentional, let the shell expand it):

```bash
helm install --create-namespace -n scaleops-system \
  --repo https://registry.scaleops.com/charts \
  --username scaleops --password "$SCALEOPS_TOKEN" \
  --set scaleopsToken="$SCALEOPS_TOKEN" \
  --set clusterName=WORKSPACE-$(kubectl config current-context) \
  scaleops scaleops
```

On OpenShift (`oc` exists and `kubectl get clusterversion` works) add `--set global.openShift=true`.
On a 401 or authentication error the token is wrong: tell the user and stop. On any other error, show it with your best guess of the cause, then stop.

## Step 5 - Wait

Poll `kubectl get pods -n scaleops-system` every 10 seconds, up to 5 minutes, until every pod is Running or Completed. Report once a minute. If a pod is CrashLoopBackOff, or Pending for more than 2 minutes, show `kubectl describe pod` and `kubectl logs --tail=50` for it, then stop.

## Step 6 - Verify

Run `kubectl get recommendations.analysis.scaleops.sh -A --no-headers | wc -l`. Zero is normal for the first 2 minutes; retry every 30 seconds for up to 3 more minutes.

## Step 7 - Open

Open the workspace URL in the user's default browser (`open` on macOS, `xdg-open` on Linux). If the cluster is not listed within 2 minutes, run `kubectl logs -n scaleops-system deploy/scaleops-agent --tail=50` and show lines mentioning token, auth, unauthorized or connection.

## Step 8 - Report

Five lines: cluster name, node count, pods ready, recommendations found, dashboard URL. Then one sentence: ScaleOps is running in read-only mode and will not change anything until automation is turned on.

## Rules

Never read, write, echo or repeat the token; only pass it through the environment variable. Never change the kube context without asking. Never delete anything.
