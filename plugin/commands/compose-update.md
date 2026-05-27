---
description: Pull latest images and recreate a Compose stack (pull + up -d). Scope-gated; critical projects need --confirm=<project>.
argument-hint: "[server] <project> [--confirm=<project>]"
allowed-tools: Bash, Read, AskUserQuestion
---

# Compose Update

Recreates containers (destructive-ish). Critical projects: confirm via
AskUserQuestion first, then run with `--confirm=<project>` (same rule as
/compose-down).

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_compose-lib.sh"

PROJECT=""; SERVER_ARG=""; TOKEN=""
set -f            # no globbing of unquoted $ARGUMENTS (review H2)
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm=*) TOKEN="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SERVER_ARG" ]; then SERVER_ARG="$1"; else PROJECT="$1"; fi ;;
  esac
  shift
done
if [ -n "$SERVER_ARG" ] && [ -z "$PROJECT" ]; then PROJECT="$SERVER_ARG"; SERVER_ARG=""; fi
[ -n "$PROJECT" ] || { echo "Usage: /compose-update [server] <project> [--confirm=<project>]" >&2; exit 1; }
[[ "$PROJECT" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid project name" >&2; exit 1; }

NAME="$(resolve_server "$SERVER_ARG")"
build_ssh "$NAME"; echo_target "$NAME"
is_scope_authorized "$NAME" docker_compose || {
  echo "REFUSED: scope 'docker_compose' not authorized for '$NAME'." >&2; exit 1; }
resolve_docker_cmd "$NAME"; docker_precheck

ENTRY="$(compose_find_project "$PROJECT")"
[ -n "$ENTRY" ] || { echo "ERROR: project '$PROJECT' not found." >&2; exit 1; }
if is_protected_resource "$NAME" compose_project "$PROJECT"; then
  confirm_destructive "$PROJECT" "$TOKEN" || exit 1
fi

CFG_ARGS="$(compose_config_args "$(echo "$ENTRY" | jq -r '.ConfigFiles')")"
# shellcheck disable=SC2086
"${FM_SSH[@]}" "$FM_DOCKER compose $CFG_ARGS pull"
# shellcheck disable=SC2086
if "${FM_SSH[@]}" "$FM_DOCKER compose $CFG_ARGS up -d"; then RC=0; else RC=$?; fi
[ "$RC" -eq 0 ] || { echo "ERROR: compose up failed (exit $RC)." >&2; exit "$RC"; }
echo ""; echo "Verdict: updated '$PROJECT'."; compose_ls_json | jq -r --arg p "$PROJECT" '.[] | select(.Name==$p) | .Status' || echo "(state re-query failed — update was sent)"
```
