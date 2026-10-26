# ScaleOps install runbook for AI agents

Technical reference for installing ScaleOps with an AI coding agent. The user's message carries two values copied from their ScaleOps install page: `Workspace:` (the dashboard URL, for example https://acme.scaleops.com; WORKSPACE is its subdomain, acme) and `Enable:` (the options they ticked). Do not ask for either.

Speed matters. The installer checks tools and the cluster itself, so launch it first and run every other step while it waits. Target: the terminal tab is open within 15 seconds of reading this page. Use as few tool calls as possible; never re-read this page or re-check something the installer already checks.

## Messages to the user

Send exactly these four messages, nothing else, no narration of tools or reasoning. Fill the angle brackets.

1. After launching the installer: `**1/4 Installer ready.** Paste your token in the ScaleOps installer tab (it shows as asterisks) and press Enter.`
2. When the tab prints `INSTALLING`: `**2/4 Installing on <CLUSTER>.** About 2 minutes. You can leave this tab; I will report when it is done.`
3. When the tab prints `INSTALL OK` and the MCP is registered: `**3/4 Pods running, MCP connected.** Building your report.`
4. The report from the last section, then stop.

If anything fails, send one line saying what failed and what the user can do, then stop.

## Step 1 - Launch the installer

Map the `Enable:` line to Helm flags and collect them into FLAGS (may be empty). Use the line as given; do not ask whether to adjust and do not label anything as recommended.

| Option in `Enable:` | Helm flag |
|---|---|
| AI SRE Agent | nothing; it is on by default. If it is absent from the line, add `--set scaleopsAI.enabled=false` |
| GPU optimization | `--set gpu.enabled=true` |
| Network observability | `--set global.observability.enabled=true` |
| OpenShift | `--set global.openShift=true` |

Write the script below to a temp file, substituting FLAGS only, and launch it. It is interactive, so it must run in a terminal the user can see and type into, never through your own command tool:

- Claude Code desktop: use the Terminal panel tool to run `bash <path>` in a new tab titled "ScaleOps installer", then call the show-pane tool with pane `terminal` and that tab's id. Send message 1.
- Cursor or Codex: run `bash <path>` in the integrated terminal. Send message 1.
- No visible terminal available: print `bash <path>`, ask the user to run it and to tell you when it has finished.

The token never passes through the chat. The script reads it from the keyboard, passes it to helm (the ScaleOps chart registry requires it for authentication), and discards it. It makes no other network call.

```bash
#!/usr/bin/env bash
# ScaleOps installer. Uses only helm and kubectl. The token is read from the keyboard,
# passed to helm, and discarded. It is never printed, logged or sent anywhere else.
set -u
FLAGS="__FLAGS__"
REPO="https://registry.scaleops.com/charts"
echo
echo "  ScaleOps installer"
echo "  ------------------"
command -v kubectl >/dev/null 2>&1 || { echo "  MISSING kubectl - install it from kubernetes.io and run again"; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "  MISSING helm - install it from helm.sh and run again"; exit 1; }
CLUSTER=$(kubectl config current-context 2>/dev/null) || { echo "  NO CLUSTER - no current kube context"; exit 1; }
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "${NODES:-0}" -gt 0 ] || { echo "  NO CLUSTER - $CLUSTER is unreachable"; exit 1; }
echo "  Cluster   : $CLUSTER ($NODES nodes)"
echo "  Options   : ${FLAGS:-AI SRE Agent (default)}"
echo
while IFS= read -rs -t 1 -n1 junk; do :; done   # drain anything the terminal sent on startup
printf "  Paste your ScaleOps token and press Enter (shown as *): "
TOKEN=""
while IFS= read -rs -n1 ch; do
  [ -z "$ch" ] && break
  if [ "$ch" = $'\e' ]; then   # skip terminal escape sequences such as bracketed-paste markers
    while IFS= read -rs -t 1 -n1 e; do case "$e" in [~A-Za-z]) break;; esac; done; continue
  fi
  if [ "$ch" = $'\x7f' ]; then TOKEN="${TOKEN%?}"; printf '\b \b'; else TOKEN="$TOKEN$ch"; printf '*'; fi
done
echo
TOKEN=$(printf '%s' "$TOKEN" | LC_ALL=C tr -cd 'A-Za-z0-9_.:-')   # keep printable token characters only
if [ -z "$TOKEN" ]; then echo "  TOKEN MISSING"; exit 2; fi
printf "  Validating token ... "
if helm show chart scaleops --repo "$REPO" --username scaleops --password "$TOKEN" >/dev/null 2>&1; then
  echo "ok"
else
  echo; echo "  TOKEN REJECTED - copy it again from the install page"; unset TOKEN; exit 3
fi
echo "  INSTALLING"
if helm upgrade --install scaleops scaleops --repo "$REPO" --username scaleops --password "$TOKEN" \
  --create-namespace -n scaleops-system --set scaleopsToken="$TOKEN" \
  --set clusterName="$CLUSTER" $FLAGS >/tmp/scaleops-helm.log 2>&1; then
  echo "  Chart installed"
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
echo "  CLUSTER=$CLUSTER NODES=$NODES"
```

## Step 2 - While the installer waits

Do these now, in parallel with the user pasting the token. Do not poll the terminal yet.

Register the ScaleOps MCP using WORKSPACE from the user's message:

- Claude Code: run `claude mcp add --transport http scaleops https://WORKSPACE.scaleops.com/mcp`. If the `claude` command is not on PATH (desktop app), add this entry under `mcpServers` in `~/.claude.json`, creating the key if needed and keeping everything else in the file untouched: `"scaleops": {"type": "http", "url": "https://WORKSPACE.scaleops.com/mcp"}`. If an entry with that URL already exists, leave it.
- Cursor: add to `.cursor/mcp.json`: `{"mcpServers":{"ScaleOps":{"url":"https://WORKSPACE.scaleops.com/mcp"}}}`
- Codex: include the URL `https://WORKSPACE.scaleops.com/mcp` in the final notes for the user to add to their Codex config.

Then read the terminal tab with a long wait (60 seconds per read, not shorter), until it prints one of:

- `INSTALLING`: send message 2, then keep reading with the same long wait.
- `INSTALL OK`: delete the temp file, hide the Terminal panel with the close-pane tool (pane `terminal`; leave the tab open, it holds the log), send message 3, go to step 3.
- `TOKEN MISSING` or `TOKEN REJECTED`: run the installer again the same way and send message 1 again.
- `MISSING`, `NO CLUSTER` or `INSTALL FAILED`: report the line and stop.

Do not poll pods with kubectl; the installer already waits for them.

## Step 3 - Report

One command for the counts: `kubectl get recommendations.analysis.scaleops.sh -A --no-headers | awk '{ns[$1]=1; n++} END {print n, length(ns)}'` gives workloads and namespaces. If it prints 0, wait 30 seconds and retry up to 4 times.

If the ScaleOps MCP responds, take waste, savings, cost, risk and detected counts from its cluster overview, under-provisioned, OOM, throttling and workload views. If it does not respond (it needs a one-time browser sign-in), use the fallback lines below and add the sign-in note after the report. Do not wait for the sign-in.

Write the report as plain markdown, not inside a code block. Keep this shape exactly; one line per block; drop any Detected item whose count is 0:

> ✅ **ScaleOps is running on <CLUSTER>** · read-only until you turn automation on
>
> **Your cluster** · <N> node(s) · <W> workloads · <K> namespaces
>
> 💰 **Waste** · <P>% of requested resources unused · estimated savings **$<S>/month** · [Rightsizing](https://WORKSPACE.scaleops.com/rightSizing/workloads)
> ⚠️ **Risk, last 24h** · <M> OOM kills · <T> throttled · <O> under-provisioned · [Troubleshoot](https://WORKSPACE.scaleops.com/troubleshooting)
> 🔍 **Detected** · <J> Java · <A> AI agents · <B> MCP servers · [Workloads](https://WORKSPACE.scaleops.com/java/workloads)
>
> **Next** · ask me anything about this cluster · [invite a teammate](https://WORKSPACE.scaleops.com/users) · automate one dev namespace when ready

Fallback when the MCP has no data: replace the whole Waste, Risk or Detected line with `💰 **Waste** · collecting, check back in 15 min` (same for the other two, with their own emoji and label). Never put the word "collecting" inside a number slot. Write `1 node`, not `1 nodes`.

Sign-in note, only when the MCP did not respond, one line after the report: `One click left: type /mcp here, pick scaleops and sign in (or Connectors in the sidebar, Authenticate next to Scaleops). Then ask me for the numbers.` The sign-in cannot be started by the agent; an MCP server added to `~/.claude.json` during a session is loaded by the next session, so in the desktop app the user may need to start a new session first. Say so only if `/mcp` does not list scaleops.

Nothing else after the report: no summary of what happened, no list of pods, no cleanup notes.

## Rules

Never read, print, log or store the token; it exists only inside the installer process. Never change the kube context. Never delete anything except the temp installer file. Never install software on the user's machine.
