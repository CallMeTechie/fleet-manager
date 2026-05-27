---
description: List Docker Compose projects on a server with status, container counts, and config paths. Read-only.
allowed-tools: Bash, Read
---

# Compose List

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_compose-lib.sh"

NAME="$(resolve_server "$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')")"
build_ssh "$NAME"; echo_target "$NAME"
resolve_docker_cmd "$NAME"; docker_precheck

RAW="$(compose_ls_json)"
COUNT="$(echo "$RAW" | jq 'length' 2>/dev/null || echo 0)"
if [ "$COUNT" = "0" ]; then echo "No compose projects on $NAME."; exit 0; fi

printf "%-22s %-16s %s\n" "PROJECT" "STATUS" "CONFIG"
# `|| true`: don't let a jq hiccup abort the command under pipefail after the header.
echo "$RAW" | jq -r '.[] | [.Name, .Status, .ConfigFiles] | @tsv' \
  | while IFS=$'\t' read -r n s c; do printf "%-22s %-16s %s\n" "$n" "$s" "$c"; done || true

ACTIVE="$(echo "$RAW" | jq '[.[] | select(.Status | startswith("running"))] | length')"
echo ""; echo "Verdict: $ACTIVE running of $COUNT total"
```
