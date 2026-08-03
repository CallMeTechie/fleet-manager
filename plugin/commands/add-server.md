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

Otherwise (new server): run the **intake dialogue from `/first-run` step 1**
yourself, here in the main thread, then dispatch the `fleet-intake` subagent with
the collected values exactly as `/first-run` step 2 describes, and handle its
return value as `/first-run` step 3 describes.

The subagent has no `AskUserQuestion` tool — subagents cannot reach the user — so
it must never be dispatched before every answer is in hand.

Two differences from `/first-run`:

- The inventory is not empty, so `<name>` must not collide with an existing
  profile. The bash block above already reports a collision for an argument-supplied
  name; re-check with `profile_exists` after the dialogue if the user typed a
  different one.
- Do not assume the new server should become active. Dispatch with
  `set_active=no`, then ask via `AskUserQuestion` after a successful intake, and
  only run `set_active <name>; write_inventory` if the user says yes.
