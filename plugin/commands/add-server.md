---
description: Add another server to the fleet-manager inventory (interactive). Protects existing profiles from accidental overwrite.
allowed-tools: Bash, Read, Write, Edit, Task, AskUserQuestion
---

# Add Server

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"
mkdir -p "$FM_SERVERS_DIR"
NAME="$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')"
if [ -n "$NAME" ] && profile_exists "$NAME"; then
  echo "RE_ADD: server '$NAME' already exists"
fi
```

**Re-Add protection (Concern 1):** If the script prints `RE_ADD: …`, the server
already exists. Do **not** overwrite it blindly (that would lose Scoped Operations,
Protected Resources and Notes). Ask the user via `AskUserQuestion`:
"Server `<name>` existiert. Was tun?" → Options:

- "Aktiv setzen (`/use`)" → run `set_active <name>; write_inventory` and stop.
- "Update-Modus" → update only the Connection section + newly discovered
  Identity/Discovered-State fields; **preserve** Scoped Operations, Protected
  Resources and Notes.
- "Abbrechen".

Otherwise (new server) use Claude's native **Task tool** to invoke the subagent
named `fleet-intake` with the same instruction as `/first-run` but for an additional
server, and ask at the end whether to make it the active server.
