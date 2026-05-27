---
description: Start a Compose stack on a server (up -d). Scope-gated (docker_compose). Use --file <abs path> to bring up a not-yet-indexed stack.
argument-hint: "[server] <project | --file /abs/path.yml>"
allowed-tools: Bash, Read
---

# Compose Up

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_compose-lib.sh"

FILE=""; PROJECT=""; SERVER_ARG=""
set -f            # no globbing of unquoted $ARGUMENTS (review H2)
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --file) shift; FILE="${1:-}" ;;
    --file=*) FILE="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SERVER_ARG" ]; then SERVER_ARG="$1"; else PROJECT="$1"; fi ;;
  esac
  shift
done
# Single positional = project (active server assumed)
if [ -n "$SERVER_ARG" ] && [ -z "$PROJECT" ] && [ -z "$FILE" ]; then PROJECT="$SERVER_ARG"; SERVER_ARG=""; fi

# Exactly one of PROJECT / FILE
if { [ -n "$PROJECT" ] && [ -n "$FILE" ]; } || { [ -z "$PROJECT" ] && [ -z "$FILE" ]; }; then
  echo "Usage: /compose-up [server] <project>   OR   /compose-up [server] --file /abs/path.yml" >&2
  exit 1
fi

NAME="$(resolve_server "$SERVER_ARG")"
build_ssh "$NAME"; echo_target "$NAME"
is_scope_authorized "$NAME" docker_compose || {
  echo "REFUSED: scope 'docker_compose' not authorized for '$NAME'. Tick it in the profile (or re-run /add-server)." >&2; exit 1; }
resolve_docker_cmd "$NAME"; docker_precheck

if [ -n "$FILE" ]; then
  if ! [[ "$FILE" =~ ^/[A-Za-z0-9/_.-]+\.ya?ml$ ]]; then
    echo "ERROR: --file needs an ABSOLUTE path to a .yml/.yaml file (got '$FILE')." >&2; exit 1
  fi
  case "$FILE" in *..*) echo "ERROR: --file path must not contain '..' (no traversal)." >&2; exit 1 ;; esac
  if "${FM_SSH[@]}" "test -f '$FILE'"; then :; else
    rc=$?
    if [ "$rc" -eq 255 ]; then echo "ERROR: SSH to $NAME failed." >&2; else echo "ERROR: '$FILE' not found on $NAME." >&2; fi
    exit 1
  fi
  "${FM_SSH[@]}" "$FM_DOCKER compose -f $FILE up -d"
else
  ENTRY="$(compose_find_project "$PROJECT")"
  if [ -z "$ENTRY" ]; then
    echo "ERROR: project '$PROJECT' is not indexed yet (never started)." >&2
    echo "  For a first deploy use:  /compose-up $NAME --file /abs/path/docker-compose.yml" >&2
    exit 1
  fi
  CFG_ARGS="$(compose_config_args "$(echo "$ENTRY" | jq -r '.ConfigFiles')")"
  # shellcheck disable=SC2086
  "${FM_SSH[@]}" "$FM_DOCKER compose $CFG_ARGS up -d"
fi
echo ""; echo "Verdict:"; compose_ls_json | jq -r '.[] | [.Name, .Status] | @tsv' || echo "(state re-query failed — action was sent)"
```
