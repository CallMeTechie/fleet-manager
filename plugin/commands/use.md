---
description: Set the active fleet-manager server. Subsequent commands without a server argument target it.
allowed-tools: Bash, Read, Edit
---

# Use (set active server)

Set the active server to `$ARGUMENTS`. Run:

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"

NAME="$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')"
[ -n "$NAME" ] || { echo "Usage: /use <server-name>"; list_server_names; exit 1; }

set_active "$NAME"            # validates existence; prints list + exits non-zero if unknown
write_inventory
echo "Active server is now: $NAME"

# Load FM_* to echo the target. If the profile is invalid (e.g. /use before
# /setup-ssh), surface it instead of silently swallowing and crashing later (C2).
if build_ssh "$NAME" >/dev/null 2>&1; then
  echo_target "$NAME"
else
  echo "WARN: '$NAME' is active but its profile is incomplete/invalid — run /setup-ssh $NAME before /diag or /status." >&2
fi
```

`set_active` is the only place the active server is recorded — do not mirror the
name into any other file. If the server does not exist, `set_active` prints the
available list and exits non-zero — relay that to the user.
