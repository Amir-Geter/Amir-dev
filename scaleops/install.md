# ScaleOps install runbook for AI agents

This page is the technical reference for installing ScaleOps with an AI coding agent. The user's message carries two values copied from their ScaleOps install page: `Workspace:` (the dashboard URL, for example https://acme.scaleops.com; WORKSPACE is its subdomain, acme) and `Enable:` (the install options they ticked). Do not ask for either.

Work through the steps in order. Tell the user what you are doing in one short line per step. Do not ask questions you can answer by running a command. Only stop where a step says to stop.

## Step 0 - Environment

Detect which tool you are running in: Claude Code, Cursor, or Codex. Detect the OS with `uname -s`. Remember both; they decide how you open the terminal in step 4 and how you register the MCP in step 7.

## Step 1 - Tools

Run `kubectl version --client` and `helm version`. If either is missing, tell the user which one and how to install it (helm.sh, kubernetes.io), then stop. Do not install anything yourself.

## Step 2 - Cluster

Run `kubectl config current-context` and `kubectl get nodes --no-headers | wc -l`. State the context name and node count in one line and continue. If there is no context or the cluster is unreachable, tell the user and stop.

## Step 3 - Options

Read the `Enable:` line from the user's message. It lists exactly what the user ticked on the install page; use it as given. Do not ask whether to adjust and do not label anything as recommended. State the selection in one line, then map it to Helm flags:

| Option in `Enable:` | Helm flag |
|---|---|
| AI SRE Agent | nothing; it is on by default. If it is absent from the line, add `--set scaleopsAI.enabled=false` |
| GPU optimization | `--set gpu.enabled=true` |
| Network observability | `--set global.observability.enabled=true` |
| OpenShift | `--set global.openShift=true` (and use `oc config current-context` for the cluster name) |

If the line is missing entirely, use no flags. Collect the result into FLAGS (may be empty).

## Step 4 - Token and install

The token must never pass through the chat. The installer below uses only helm and kubectl: it reads the token from the keyboard, passes it to helm (the ScaleOps chart registry requires it for authentication), and discards it. It makes no other network call. Write it to a temp file, substituting CLUSTER (the context name from step 2) and FLAGS. The installer is interactive: it waits for the user to paste the token. It must run in a terminal the user can see and type into, never through your own command tool, which has no keyboard:

- Claude Code: use the Terminal panel tool to run `bash <path>` in a new terminal tab titled "ScaleOps installer". Running a command there does not open the panel for the user, so immediately after, call the show-pane tool with pane `terminal` and that tab's id to bring the panel forward. Then tell the user: "The installer is waiting in the ScaleOps installer tab. Click inside the tab, paste your token (it shows as asterisks) and press Enter." Read the tab's output to follow progress.
- Cursor or Codex: run `bash <path>` in the integrated terminal.
- If you have no way to run a command in a visible terminal, print `bash <path>` and ask the user to run it in their terminal and tell you when it has finished.

```bash
#!/usr/bin/env bash
# ScaleOps installer. Uses only helm and kubectl. The token is read from the keyboard,
# passed to helm, and discarded. It is never printed, logged or sent anywhere else.
set -u
CLUSTER="__CLUSTER__"
FLAGS="__FLAGS__"
REPO="https://registry.scaleops.com/charts"
echo
echo "  ScaleOps installer"
echo "  ------------------"
echo "  Cluster   : $CLUSTER"
echo "  Options   : ${FLAGS:-AI SRE Agent (default)}"
echo
printf "  Paste your ScaleOps token and press Enter (shown as *): "
TOKEN=""
while IFS= read -rs -n1 ch; do
  [ -z "$ch" ] && break
  if [ "$ch" = $'\x7f' ]; then TOKEN="${TOKEN%?}"; printf '\b \b'; else TOKEN="$TOKEN$ch"; printf '*'; fi
done
echo
if [ -z "$TOKEN" ]; then echo "  TOKEN MISSING"; exit 2; fi
printf "  Validating token ... "
if helm show chart scaleops --repo "$REPO" --username scaleops --password "$TOKEN" >/dev/null 2>&1; then
  echo "ok"
else
  echo; echo "  TOKEN REJECTED - copy it again from the install screen"; unset TOKEN; exit 3
fi
printf "  Installing chart ... "
if helm upgrade --install scaleops scaleops --repo "$REPO" --username scaleops --password "$TOKEN" \
  --create-namespace -n scaleops-system --set scaleopsToken="$TOKEN" \
  --set clusterName="$CLUSTER" $FLAGS >/tmp/scaleops-helm.log 2>&1; then
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
echo "  INSTALL OK"
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

Register the ScaleOps MCP so this tool can query the cluster, using WORKSPACE from the user's message:

- Claude Code: run `claude mcp add --transport http scaleops https://WORKSPACE.scaleops.com/mcp`. If the `claude` command is not on PATH (desktop app), instead add this entry under `mcpServers` in `~/.claude.json`, creating the key if needed and keeping everything else in the file untouched: `"scaleops": {"type": "http", "url": "https://WORKSPACE.scaleops.com/mcp"}`
- Cursor: add to `.cursor/mcp.json`: `{"mcpServers":{"ScaleOps":{"url":"https://WORKSPACE.scaleops.com/mcp"}}}`
- Codex: tell the user to add the MCP server URL `https://WORKSPACE.scaleops.com/mcp` to their Codex config.

Tell the user: "The ScaleOps MCP is registered. The first time it is used, a browser window opens to sign in; approve it once."

## Step 8 - Report

If the MCP is available, use its cluster overview, workload list and under-provisioned views for the numbers. Otherwise use kubectl: nodes and allocatable from `kubectl get nodes`, workloads and namespaces from the Recommendation objects. Any number not yet available is written as "collecting, check back in 15 min". Use the `Workspace:` URL from the user's message for the links. Keep this exact shape:

```
✅ ScaleOps is running on <CLUSTER>
   Read-only mode. Nothing changes until you turn automation on.

YOUR CLUSTER
   <N> nodes
   <W> workloads · <K> namespaces
   $<R> / month

WHAT WE FOUND
   💰  <P>% of requested resources are unused
       Estimated savings: $<S> / month (refines over 24h)
       → <WORKSPACE_URL>/rightSizing/workloads

   ⚠️  Last 24h
       <M> OOM kills
       <T> throttled workloads
       <O> under-provisioned workloads
       → <WORKSPACE_URL>/troubleshooting

   🔍  Special workloads detected, policies assigned
       <J> Java services
       <A> AI agents
       <B> MCP servers
       → <WORKSPACE_URL>/java/workloads

NEXT
   1. Ask me anything about this cluster (ScaleOps MCP is connected)
   2. Invite a teammate → <WORKSPACE_URL>/users
   3. Automate one dev namespace and watch the savings land
```

Omit any line in the Detected block whose count is 0. Add a `<G> GPU workloads` line there only when the count is above 0.

## Rules

Never read, print, log or store the token; it exists only inside the installer process. Never change the kube context. Never delete anything. Never install software on the user's machine.
