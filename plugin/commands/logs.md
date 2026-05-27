---
description: View system logs on a server (journalctl, fallback /var/log/syslog). Read-only. For container logs use /compose-logs.
argument-hint: "[server] [unit] [--tail N]"
allowed-tools: Bash, Read
---

# Logs

`/logs` reads the **system** journal. For a container/app log use `/compose-logs <project>`.

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"

TAIL=100; UNIT=""; SERVER_ARG=""
set -f            # no globbing of unquoted $ARGUMENTS (review H2)
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --tail) shift; TAIL="${1:-100}" ;;
    --tail=*) TAIL="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SERVER_ARG" ]; then SERVER_ARG="$1"; else UNIT="$1"; fi ;;
  esac
  shift
done
[[ "$TAIL" =~ ^[0-9]+$ ]] || { echo "Invalid --tail" >&2; exit 1; }
if [ -n "$UNIT" ]; then [[ "$UNIT" =~ ^[A-Za-z0-9@._-]+$ ]] || { echo "Invalid unit" >&2; exit 1; }; fi

NAME="$(resolve_server "$SERVER_ARG")"
build_ssh "$NAME"; echo_target "$NAME"
is_scope_authorized "$NAME" system_monitoring || {
  echo "REFUSED: scope 'system_monitoring' not authorized for '$NAME'." >&2; exit 1; }

if "${FM_SSH[@]}" "command -v journalctl >/dev/null 2>&1"; then
  if [ -n "$UNIT" ]; then JC="journalctl -n $TAIL -u $UNIT --no-pager"; else JC="journalctl -n $TAIL --no-pager"; fi
  OUT="$("${FM_SSH[@]}" "$JC 2>&1" || true)"
  if echo "$OUT" | grep -qiE "permission denied|not seeing messages from other users"; then
    echo "WARN  journalctl permission denied — add the SSH user to the 'systemd-journal' or 'adm' group." >&2
  fi
  if [ -z "$OUT" ] && [ -n "$UNIT" ]; then
    echo "(no journal entries for unit '$UNIT' — for container logs try: /compose-logs $UNIT)"
  else
    printf '%s\n' "$OUT"
  fi
else
  echo "(journalctl not present — falling back to /var/log/syslog)"
  "${FM_SSH[@]}" "tail -n $TAIL /var/log/syslog 2>/dev/null" || echo "(no /var/log/syslog either)"
fi
```
