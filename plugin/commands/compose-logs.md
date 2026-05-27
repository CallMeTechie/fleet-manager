---
description: Show logs for a Compose project on a server. Read-only.
argument-hint: "[server] <project> [--tail N]"
allowed-tools: Bash, Read
---

# Compose Logs

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_compose-lib.sh"

TAIL=100; PROJECT=""; SERVER_ARG=""
set -f            # no globbing of unquoted $ARGUMENTS (review H2)
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --tail) shift; TAIL="${1:-100}" ;;
    --tail=*) TAIL="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SERVER_ARG" ]; then SERVER_ARG="$1"; else PROJECT="$1"; fi ;;
  esac
  shift
done
# If only one positional was given, it is the project (active server assumed).
if [ -n "$SERVER_ARG" ] && [ -z "$PROJECT" ]; then PROJECT="$SERVER_ARG"; SERVER_ARG=""; fi
[ -n "$PROJECT" ] || { echo "Usage: /compose-logs [server] <project> [--tail N]" >&2; exit 1; }
[[ "$PROJECT" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid project name" >&2; exit 1; }
[[ "$TAIL" =~ ^[0-9]+$ ]] || { echo "Invalid --tail" >&2; exit 1; }

NAME="$(resolve_server "$SERVER_ARG")"
build_ssh "$NAME"; echo_target "$NAME"
resolve_docker_cmd "$NAME"; docker_precheck

ENTRY="$(compose_find_project "$PROJECT")"
[ -n "$ENTRY" ] || { echo "ERROR: project '$PROJECT' not found in compose ls." >&2; exit 1; }
CF="$(echo "$ENTRY" | jq -r '.ConfigFiles')"
CFG_ARGS="$(compose_config_args "$CF")"
# shellcheck disable=SC2086  # CFG_ARGS is validated (no spaces in paths); intentional split into -f args
"${FM_SSH[@]}" "$FM_DOCKER compose $CFG_ARGS logs --tail $TAIL"
```
