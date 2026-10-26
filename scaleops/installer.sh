#!/usr/bin/env bash
# ScaleOps installer. Uses only helm and kubectl. The token is read from the keyboard,
# passed to helm, and discarded. It is never printed, logged or sent anywhere else.
set -u
# Usage: bash installer.sh [terminal|dialog] ["<helm flags>"]
MODE="${1:-terminal}"   # "terminal": read the token here. "dialog": ask in a pop-up window
FLAGS="${2:-}"          # extra helm flags, for example "--set gpu.enabled=true"
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
[ "$NODES" = 1 ] && NL=node || NL=nodes; echo "  Cluster   : $CLUSTER ($NODES $NL)"
echo "  Options   : ${FLAGS:-AI SRE Agent (default)}"
echo
TOKEN=""
if [ "$MODE" = "dialog" ]; then
  say "WAITING FOR TOKEN in the ScaleOps pop-up window"
  SAFE=$(printf '%s' "$CLUSTER" | LC_ALL=C tr -cd 'A-Za-z0-9._:/@-')
  if command -v osascript >/dev/null 2>&1; then
    TOKEN=$(osascript -e "display dialog \"Paste your ScaleOps token to install on $SAFE\" with title \"ScaleOps installer\" default answer \"\" with hidden answer buttons {\"Cancel\", \"Install\"} default button \"Install\" giving up after 600" -e 'text returned of result' 2>/dev/null)
  elif command -v zenity >/dev/null 2>&1; then
    TOKEN=$(zenity --password --title="ScaleOps installer - paste your token" 2>/dev/null)
  elif command -v kdialog >/dev/null 2>&1; then
    TOKEN=$(kdialog --title "ScaleOps installer" --password "Paste your ScaleOps token" 2>/dev/null)
  else
    say "NO DIALOG - run this installer in a terminal instead"; exit 5
  fi
else
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
fi
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
