---
description: Stop a Compose stack on a server. Default 'stop' (keeps it indexed); --remove for full 'down'. Critical projects need --confirm=<project>.
argument-hint: "[server] <project> [--remove] [--confirm=<project>]"
allowed-tools: Bash, Read, AskUserQuestion
---

# Compose Down

For a **critical** project this command MUST first confirm the server + project
with the user via AskUserQuestion, then run with the matching `--confirm=<project>`
token (which the user types). See the critical-gate handling below.

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_compose-lib.sh"

REMOVE=0; PROJECT=""; SERVER_ARG=""; TOKEN=""
set -f            # no globbing of unquoted $ARGUMENTS (review H2)
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --remove) REMOVE=1 ;;
    --confirm=*) TOKEN="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SERVER_ARG" ]; then SERVER_ARG="$1"; else PROJECT="$1"; fi ;;
  esac
  shift
done
if [ -n "$SERVER_ARG" ] && [ -z "$PROJECT" ]; then PROJECT="$SERVER_ARG"; SERVER_ARG=""; fi
[ -n "$PROJECT" ] || { echo "Usage: /compose-down [server] <project> [--remove] [--confirm=<project>]" >&2; exit 1; }
[[ "$PROJECT" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid project name" >&2; exit 1; }

NAME="$(resolve_server "$SERVER_ARG")"
build_ssh "$NAME"; echo_target "$NAME"
is_scope_authorized "$NAME" docker_compose || {
  echo "REFUSED: scope 'docker_compose' not authorized for '$NAME'." >&2; exit 1; }
resolve_docker_cmd "$NAME"; docker_precheck

ENTRY="$(compose_find_project "$PROJECT")"
[ -n "$ENTRY" ] || { echo "ERROR: project '$PROJECT' not found." >&2; exit 1; }

# Critical-gate: protected projects require the matching --confirm token (or env var).
if is_protected_resource "$NAME" compose_project "$PROJECT"; then
  confirm_destructive "$PROJECT" "$TOKEN" || exit 1
fi

CFG_ARGS="$(compose_config_args "$(echo "$ENTRY" | jq -r '.ConfigFiles')")"
if [ "$REMOVE" -eq 1 ]; then ACTION="down"; else ACTION="stop"; fi
# shellcheck disable=SC2086
if "${FM_SSH[@]}" "$FM_DOCKER compose $CFG_ARGS $ACTION"; then RC=0; else RC=$?; fi
[ "$RC" -eq 0 ] || { echo "ERROR: compose $ACTION failed (exit $RC)." >&2; exit "$RC"; }
echo ""
# After `down`, the project is de-indexed and absence is success (review M1).
NEWSTATUS="$(compose_ls_json | jq -r --arg p "$PROJECT" '.[] | select(.Name==$p) | .Status' 2>/dev/null || true)"
if [ "$ACTION" = "down" ]; then
  if [ -z "$NEWSTATUS" ]; then echo "Verdict: removed ('$PROJECT' no longer indexed)."; else echo "Verdict: down requested but still indexed as $NEWSTATUS — check above."; fi
else
  echo "Verdict: stopped (status: ${NEWSTATUS:-unknown})."
fi
```

**Critical-gate prose (mandatory):** when `is_protected_resource` matches, before
running, use `AskUserQuestion` to confirm with the user: "Destructive action on
CRITICAL project '<project>' on server '<NAME>'. Proceed?" Only after an explicit
yes, re-run including `--confirm=<project>`. Never fabricate the token to skip the
question. (`confirm_destructive` refuses without the token/env var as a fail-safe
against accidental runs — see the design spec for the honest limits of this gate.)
