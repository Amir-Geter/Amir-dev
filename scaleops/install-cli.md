# ScaleOps install runbook for AI agents (CLI)

## START HERE

You are installing ScaleOps on the user's current Kubernetes cluster with the ScaleOps CLI. The user does two things: paste the prompt, then click **Approve** in their browser. The token never passes through the chat, the terminal or you.

There are exactly **3 steps**. Right after step 1, create a to-do list with them and tick each one off:

1. Run the CLI
2. Wait for the result
3. Connect the MCP, report, then stop

Do nothing that is not in a step. Do not re-read this page or explore the machine. After step 3, the task is finished: stop.

**Input** from the user's message: `Workspace:` is the dashboard URL (for example https://acme.scaleops.com; WORKSPACE is its subdomain, acme). Do not ask for it.

**Install options** for this runbook are fixed. Do not ask about them or change them:

| Option | State |
|---|---|
| AI SRE Agent | enabled |
| Network observability | enabled |
| GPU optimization | disabled |

**Messages.** Send only these, filled in, and nothing else between them:

- M1 (after step 1): `**1/3 Approve in your browser.** A ScaleOps page opened; click Approve to install on <CLUSTER>.`
- M2 (when the CLI reports it is installing): `**2/3 Installing on <CLUSTER>.** About 2 minutes. You can leave this; I will report when it is done.`
- M3: the report from step 3.

On any failure send one line, what failed and what the user can do, and stop.

## Step 1 - Run the CLI

Done when: the CLI is running and you sent M1.

<!-- CLI: to be defined -->

## Step 2 - Wait for the result

Done when: the CLI finished with success, and you sent M2 along the way.

<!-- CLI output and statuses: to be defined -->

## Step 3 - Connect the MCP, report, then stop

Done when: you sent M3. Then the task is finished.

Register the MCP using WORKSPACE, with your tool's method:

| You are | Connect the MCP |
|---|---|
| Claude Code desktop app | Search the MCP connector registry for `scaleops`. If a result's URL contains `WORKSPACE.scaleops.com`, remember its directory id. Otherwise add `"scaleops": {"type": "http", "url": "https://WORKSPACE.scaleops.com/mcp"}` under `mcpServers` in `~/.claude.json`, keeping everything else in the file |
| Claude Code in a terminal | `claude mcp add --transport http scaleops https://WORKSPACE.scaleops.com/mcp` |
| Cursor | Add `"scaleops": {"url": "https://WORKSPACE.scaleops.com/mcp"}` under `mcpServers` in `~/.cursor/mcp.json`, keeping other entries |
| Codex or anything else | Give the user the MCP URL `https://WORKSPACE.scaleops.com/mcp` in the last line |

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

- Claude Code desktop app with a connector found above: one line `**Last step:** connect ScaleOps below so I can answer questions about this cluster.`, then the suggest-connectors tool with that directory id (keyword `cluster`).
- Claude Code without a connector: `**Last step:** type /mcp, pick scaleops and sign in. Then ask me anything about this cluster.`
- Cursor: `**Last step:** open Cursor Settings, MCP, and click Login next to scaleops. Then ask me anything about this cluster.`
- Codex or anything else: `**Last step:** add the MCP URL https://WORKSPACE.scaleops.com/mcp to your agent and sign in.`

## Rules

Never ask for, read, print, log or store a token. Never change the kube context. Never delete anything. Never install software on the user's machine other than the ScaleOps CLI.
