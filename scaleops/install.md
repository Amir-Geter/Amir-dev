# ScaleOps install runbook for AI agents

You are an AI coding agent. The user asked you to install ScaleOps on their current Kubernetes cluster and has approved every step below. The user's message contains their ScaleOps workspace URL; its subdomain is WORKSPACE (for https://acme.scaleops.com, WORKSPACE is acme). It may also contain an `Enable:` line with install options.

Work through the steps in order. Tell the user what you are doing in one short line per step. Do not ask questions you can answer by running a command. Only stop where a step says to stop.

## Step 0 - Environment

Detect which tool you are running in: Claude Code, Cursor, or Codex. Detect the OS with `uname -s`. Remember both; they decide how you open the terminal in step 4 and how you register the MCP in step 7.

## Step 1 - Tools

Run `kubectl version --client` and `helm version`. If either is missing, tell the user which one and how to install it (helm.sh, kubernetes.io), then stop. Do not install anything yourself.

## Step 2 - Cluster

Run `kubectl config current-context` and `kubectl get nodes --no-headers | wc -l`. State the context name and node count in one line and continue. If there is no context or the cluster is unreachable, tell the user and stop.

## Step 3 - Options

Read the `Enable:` line from the user's message. If it says `default` or is missing, the selection is: rightsizing only. Show the selection and ask once, with a selectable list where your tool supports it, whether to adjust. Options and their Helm flags:

| Option | Helm flag |
|---|---|
| GPU optimization | `--set gpu.enabled=true` |
| Network observability | `--set global.observability.enabled=true` |
| OpenShift | `--set global.openShift=true` (and use `oc config current-context` for the cluster name) |

Collect the chosen flags into FLAGS (may be empty).

## Step 4 - Token and install

The token must never pass through the chat. Write the installer below to a temp file, substituting WORKSPACE, CLUSTER (the context name from step 2) and FLAGS, then run it in a terminal the user can see:

- Claude Code: open a new terminal tab in the IDE and run `bash <path>` there.
- Cursor or Codex: run `bash <path>` in the integrated terminal.

```bash
#!/usr/bin/env bash
set -u
WORKSPACE="__WORKSPACE__"
CLUSTER="__CLUSTER__"
FLAGS="__FLAGS__"
REPO="https://registry.scaleops.com/charts"
echo
echo "  ScaleOps installer"
echo "  ------------------"
echo "  Workspace : $WORKSPACE"
echo "  Cluster   : $CLUSTER"
echo "  Options   : ${FLAGS:-rightsizing only}"
echo
read -rs -p "  Paste your ScaleOps token and press Enter: " TOKEN
echo
if [ -z "$TOKEN" ]; then echo "  TOKEN MISSING"; exit 2; fi
printf "  Validating token ... "
if helm show chart --repo "$REPO" --username scaleops --password "$TOKEN" scaleops >/dev/null 2>&1; then
  echo "ok"
else
  echo; echo "  TOKEN REJECTED - copy it again from the install screen"; unset TOKEN; exit 3
fi
printf "  Installing chart ... "
if helm upgrade --install scaleops scaleops --repo "$REPO" --username scaleops --password "$TOKEN" \
  --create-namespace -n scaleops-system --set scaleopsToken="$TOKEN" \
  --set clusterName="$WORKSPACE-$CLUSTER" $FLAGS >/tmp/scaleops-helm.log 2>&1; then
  echo "ok"
else
  echo; echo "  INSTALL FAILED"; tail -5 /tmp/scaleops-helm.log; unset TOKEN; exit 4
fi
unset TOKEN
echo "  Starting components"
for d in scaleops-admissions scaleops-agent scaleops-recommender scaleops-updater scaleops-dashboards; do
  printf "    %-22s" "$d"
  if kubectl rollout status deploy/$d -n scaleops-system --timeout=240s >/dev/null 2>&1; then echo "ready"; else echo "not ready"; fi
done
echo
echo "  INSTALL OK - dashboard: https://$WORKSPACE.scaleops.com"
```

Then read the terminal output:
- `TOKEN REJECTED`: tell the user the token was not accepted and run the installer again.
- `INSTALL FAILED`: show the lines after it and stop.
- `INSTALL OK`: continue.

Delete the temp file afterwards.

## Step 5 - Wait

Poll `kubectl get pods -n scaleops-system` every 10 seconds, up to 5 minutes, until every pod is Running or Completed. If a pod is CrashLoopBackOff, or Pending for more than 2 minutes, show `kubectl describe pod` and `kubectl logs --tail=50` for it, then stop.

## Step 6 - Verify

Run `kubectl get recommendations.analysis.scaleops.sh -A --no-headers | wc -l`. Zero is normal for the first 2 minutes; retry every 30 seconds for up to 3 more minutes. Report the count.

## Step 7 - MCP

Register the ScaleOps MCP so this tool can query the cluster:

- Claude Code: run `claude mcp add --transport http scaleops https://WORKSPACE.scaleops.com/mcp`
- Cursor: add to `.cursor/mcp.json`: `{"mcpServers":{"ScaleOps":{"url":"https://WORKSPACE.scaleops.com/mcp"}}}`
- Codex: tell the user to add the MCP server URL `https://WORKSPACE.scaleops.com/mcp` to their Codex config.

Tell the user: "The ScaleOps MCP is registered. The first time it is used, a browser window opens to sign in; approve it once."

## Step 8 - Report

If the MCP is available, use its cluster overview, workload list and under-provisioned views for the numbers. Otherwise use kubectl: nodes and allocatable from `kubectl get nodes`, workloads and namespaces from the Recommendation objects. Any number not yet available is written as "collecting, check back in 15 min". Keep this exact shape:

```
ScaleOps is running on <CLUSTER>. Read-only: nothing changes until you turn automation on.

Cluster    <N> nodes, <X> vCPU / <Y> GB allocatable, <W> workloads in <K> namespaces.
Waste      <P>% of requested CPU and memory unused. First savings estimate $<S>/month, refines over 24h.  -> https://WORKSPACE.scaleops.com/rightSizing/workloads
Risk       <O> under-provisioned workloads, <M> OOM kills, <T> throttled in the last 24h.                  -> https://WORKSPACE.scaleops.com/troubleshooting
Detected   <A> AI agents, <B> MCP servers, <J> Java services, <G> GPU workloads. Policies assigned.      -> https://WORKSPACE.scaleops.com/java/workloads

Next steps
1. Ask me anything about this cluster. The ScaleOps MCP is connected.
2. Invite a teammate: https://WORKSPACE.scaleops.com/users
3. When ready, automate one dev namespace and watch the savings land.
```

## Rules

Never read, print, log or store the token; it exists only inside the installer process. Never change the kube context. Never delete anything. Never install software on the user's machine.
