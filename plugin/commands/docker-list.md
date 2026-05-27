---
description: List all Docker containers on a server (compose-tagged + standalone). Read-only. --all includes stopped.
argument-hint: "[server] [--all]"
allowed-tools: Bash, Read
---

# Docker List

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_compose-lib.sh"

ALL=0; SERVER_ARG=""
set -f            # no globbing of unquoted $ARGUMENTS (review H2)
# shellcheck disable=SC2086  # intentional: iterate ARGUMENTS as words
for a in ${ARGUMENTS:-}; do
  case "$a" in
    --all) ALL=1 ;;
    --*) echo "Unknown flag: $a" >&2; exit 1 ;;
    *) SERVER_ARG="$a" ;;
  esac
done

NAME="$(resolve_server "$SERVER_ARG")"
build_ssh "$NAME"; echo_target "$NAME"
resolve_docker_cmd "$NAME"; docker_precheck

FMT='{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Label "com.docker.compose.project"}}'
if [ "$ALL" -eq 1 ]; then PS_ARGS="ps --all"; else PS_ARGS="ps"; fi
if RAW="$("${FM_SSH[@]}" "$FM_DOCKER $PS_ARGS --format '$FMT'" 2>/dev/null)"; then :; else
  echo "ERROR: 'docker ps' failed on $NAME (daemon down or permission?)." >&2; exit 1
fi
[ -z "$RAW" ] && { echo "No containers (running)."; exit 0; }

printf "%-24s %-34s %-16s %s\n" "NAME" "IMAGE" "STATUS" "PROJECT"
echo "$RAW" | while IFS=$'\t' read -r n img st proj; do
  printf "%-24s %-34s %-16s %s\n" "$n" "$img" "$st" "${proj:-(standalone)}"
done
```
