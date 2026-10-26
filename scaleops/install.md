# ScaleOps install runbook for AI agents

## START HERE

You are installing ScaleOps on the user's current Kubernetes cluster. There are exactly **5 steps**. Before doing anything else, create a to-do list with these five items, then work through them in order and tick each one off:

1. Write the installer
2. Launch the installer
3. Connect the ScaleOps MCP
4. Wait for the install
5. Report, then stop

Do nothing that is not in a step. Do not re-read this page, re-check what the installer checks, or explore the machine. After step 5, the task is finished: stop.

**Inputs** from the user's message: `Workspace:` is the dashboard URL (for example https://acme.scaleops.com; WORKSPACE is its subdomain, acme). `Enable:` lists the options the user ticked. Do not ask for either.

**Your tool.** Find your row once and use only that row everywhere below.

| You are | Launch the installer (step 2) | Connect the MCP (step 3) | Read the result (step 4) |
|---|---|---|---|
| Claude Code desktop app | Terminal panel tool: run `bash <path>` in a new tab titled "ScaleOps installer", then show-pane tool with pane `terminal` and that tab id | Registry first, then `~/.claude.json` (see step 3) | Read-terminal tool on that tab, 60 s waits |
| Claude Code in a terminal | You cannot type into it. Tell the user to run `bash <path>` in a second terminal window | `claude mcp add --transport http scaleops https://WORKSPACE.scaleops.com/mcp` | Read `/tmp/scaleops-install.status` every 30 s |
| Cursor | Your terminal is read-only, so do not run it yourself. Tell the user: open the terminal panel (View, Terminal), run `bash <path>`, paste the token there | Add `"scaleops": {"url": "https://WORKSPACE.scaleops.com/mcp"}` under `mcpServers` in `~/.cursor/mcp.json`, creating the file or key if needed and keeping other entries | Read `/tmp/scaleops-install.status` every 30 s |
| Codex | Run `bash <path>` in the integrated terminal | Tell the user to add `https://WORKSPACE.scaleops.com/mcp` to their Codex MCP config | Read the command output when it returns |
| Anything else | Tell the user to run `bash <path>` in their terminal | Give the user the MCP URL `https://WORKSPACE.scaleops.com/mcp` | Read `/tmp/scaleops-install.status` every 30 s if you can read files; otherwise ask the user to paste the last 3 lines |

**Messages.** Send only these, filled in, and nothing else between them:

- M1 (after step 2): `**1/4 Installer ready.** Paste your ScaleOps token in the installer terminal (it shows as asterisks) and press Enter.` If the user has to run it themselves, use instead: `**1/4 Installer ready.** Open your terminal, run the command below, paste your ScaleOps token (it shows as asterisks) and press Enter. I will follow the progress from here.` followed by the command in a code block.
- M2 (when the installer prints `INSTALLING`, if you can see it live): `**2/4 Installing on <CLUSTER>.** About 2 minutes. You can leave this; I will report when it is done.`
- M3 (after step 4): `**3/4 Pods running.** Building your report.`
- M4: the report from step 5.

On any failure send one line, what failed and what the user can do, and stop.

## Step 1 - Write the installer

Done when: the script is saved to a temp file.

Map `Enable:` to Helm flags and collect them into FLAGS (may be empty). Use the line as given; do not ask about it.

| Option in `Enable:` | Helm flag |
|---|---|
| AI SRE Agent | nothing, it is on by default. If it is absent, add `--set scaleopsAI.enabled=false` |
| GPU optimization | `--set gpu.enabled=true` |
| Network observability | `--set global.observability.enabled=true` |
| OpenShift | `--set global.openShift=true` |

Save this script to a temp file, replacing `__FLAGS__` with FLAGS. It uses only helm and kubectl, checks the tools and cluster itself, reads the token from the keyboard, passes it to helm (the ScaleOps chart registry requires it), and discards it. It makes no other network call. The token never passes through the chat.

```bash
#!/usr/bin/env bash
# ScaleOps installer. Uses only helm and kubectl. The token is read from the keyboard,
# passed to helm, and discarded. It is never printed, logged or sent anywhere else.
set -u
FLAGS="__FLAGS__"
REPO="https://registry.scaleops.com/charts"
STATUS=/tmp/scaleops-install.status   # progress markers only, never the token
: > "$STATUS"
say() { echo "  $1"; echo "$1" >> "$STATUS"; }
echo
echo "  ScaleOps installer"
echo "  ------------------"
command -v kubectl >/dev/null 2>&1 || { say "MISSING kubectl - install it from kubernetes.io and run again"; exit 1; }
command -v helm    >/dev/null 2>&1 || { say "MISSING helm - install it from helm.sh and run again"; exit 1; }
CLUSTER=$(kubectl config current-context 2>/dev/null) || { say "NO CLUSTER - no current kube context"; exit 1; }
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "${NODES:-0}" -gt 0 ] || { say "NO CLUSTER - $CLUSTER is unreachable"; exit 1; }
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
if [ -z "$TOKEN" ]; then say "TOKEN MISSING"; exit 2; fi
printf "  Validating token ... "
if helm show chart scaleops --repo "$REPO" --username scaleops --password "$TOKEN" >/dev/null 2>&1; then
  echo "ok"
else
  echo; say "TOKEN REJECTED - copy it again from the install page"; unset TOKEN; exit 3
fi
say "INSTALLING on $CLUSTER"
if helm upgrade --install scaleops scaleops --repo "$REPO" --username scaleops --password "$TOKEN" \
  --create-namespace -n scaleops-system --set scaleopsToken="$TOKEN" \
  --set clusterName="$CLUSTER" $FLAGS >/tmp/scaleops-helm.log 2>&1; then
  echo "  Chart installed"
else
  echo; say "INSTALL FAILED"; tail -5 /tmp/scaleops-helm.log | tee -a "$STATUS"; unset TOKEN; exit 4
fi
unset TOKEN
echo "  Starting components"
for d in scaleops-admissions scaleops-agent scaleops-recommender scaleops-updater scaleops-dashboards; do
  printf "    %-22s" "$d"
  if kubectl rollout status deploy/$d -n scaleops-system --timeout=240s >/dev/null 2>&1; then echo "ready"; else echo "not ready"; fi
done
echo
say "INSTALL OK"
say "CLUSTER=$CLUSTER NODES=$NODES"
```

## Step 2 - Launch the installer

Done when: the installer is running where the user can type, and you sent M1.

Use your row's "Launch" cell. The installer is interactive, so never run it through a tool the user cannot type into. Target: this happens within 15 seconds of reading this page.

## Step 3 - Connect the ScaleOps MCP

Done when: the MCP entry exists for your tool. Do this while the user pastes the token.

Use your row's "Connect" cell. Claude Code desktop app only: first search the MCP connector registry for `scaleops`; if a result's URL contains `WORKSPACE.scaleops.com`, remember its directory id for step 5 and skip the file. Otherwise add `"scaleops": {"type": "http", "url": "https://WORKSPACE.scaleops.com/mcp"}` under `mcpServers` in `~/.claude.json`, keeping everything else in the file. If an entry with that URL already exists, leave it.

## Step 4 - Wait for the install

Done when: the installer printed `INSTALL OK`, and you sent M3. The status file `/tmp/scaleops-install.status` holds the same lines as the terminal, without the token; it is reset each time the installer starts.

Use your row's "Read" cell. Act on the first of these lines that appears:

| Installer prints | Do |
|---|---|
| `INSTALLING` | Send M2, keep waiting |
| `INSTALL OK` | Note `CLUSTER=` and `NODES=`. Delete the temp file. Claude Code desktop app: hide the terminal panel with the close-pane tool (pane `terminal`), leave the tab open. Send M3 |
| `TOKEN MISSING` or `TOKEN REJECTED` | Launch the installer again (step 2) and send M1 again |
| `MISSING`, `NO CLUSTER` or `INSTALL FAILED` | Report that line and stop |

Do not poll pods; the installer already waits for them.

## Step 5 - Report, then stop

Done when: you sent M4. Then the task is finished.

Get workloads and namespaces with one command: `kubectl get recommendations.analysis.scaleops.sh -A --no-headers | awk '{ns[$1]=1; n++} END {print n, length(ns)}'`. If it prints 0, wait 30 seconds and retry, up to 4 times.

If the ScaleOps MCP answers, take waste, savings, risk and detected counts from its cluster overview, under-provisioned, OOM, throttling and workload views. If it does not answer, use the fallback lines. Do not wait for it.

Write the report as plain markdown, not in a code block, in exactly this shape. Drop any Detected item whose count is 0:

> ✅ **ScaleOps is running on <CLUSTER>** · read-only until you turn automation on
>
> **Your cluster** · <N> node(s) · <W> workloads · <K> namespaces
>
> 💰 **Waste** · <P>% of requested resources unused · estimated savings **$<S>/month** · [Rightsizing](https://WORKSPACE.scaleops.com/rightSizing/workloads)
> ⚠️ **Risk, last 24h** · <M> OOM kills · <T> throttled · <O> under-provisioned · [Troubleshoot](https://WORKSPACE.scaleops.com/troubleshooting)
> 🔍 **Detected** · <J> Java · <A> AI agents · <B> MCP servers · [Workloads](https://WORKSPACE.scaleops.com/java/workloads)
>
> **Next** · ask me anything about this cluster · [invite a teammate](https://WORKSPACE.scaleops.com/users) · automate one dev namespace when ready

Fallback: when a line has no data, replace the whole line with its emoji and label plus `collecting, check back in 15 min`. Never put words in a number slot. Write `1 node`, not `1 nodes`.

End with exactly one of these, then stop:

- Claude Code desktop app with a connector found in step 3: one line `**Last step:** connect ScaleOps below so I can answer questions about this cluster.`, then the suggest-connectors tool with that directory id (keyword `cluster`).
- Claude Code without a connector: `**Last step:** type /mcp, pick scaleops and sign in. Then ask me anything about this cluster.`
- Cursor: `**Last step:** open Cursor Settings, MCP, and click Login next to scaleops. Then ask me anything about this cluster.`
- Codex or anything else: `**Last step:** add the MCP URL https://WORKSPACE.scaleops.com/mcp to your agent and sign in.`

## Rules

Never read, print, log or store the token; it exists only inside the installer process. Never change the kube context. Never delete anything except the temp installer file. Never install software on the user's machine.
