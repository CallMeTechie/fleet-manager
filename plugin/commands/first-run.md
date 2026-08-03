---
description: Onboard your first server into fleet-manager via a guided intake dialogue.
allowed-tools: Bash, Read, Write, Edit, Task, AskUserQuestion
---

# First Run

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"
mkdir -p "$FM_SERVERS_DIR"
if [ -n "$(list_server_names)" ]; then
  echo "Inventory already has servers. Use /add-server to add another, or /list-servers to view them."
  exit 0
fi
echo "No servers yet — starting intake."
```

If the inventory is empty, run the intake dialogue below **yourself**, here in the
main thread. The `fleet-intake` subagent has no `AskUserQuestion` tool — subagents
cannot reach the user — so it is dispatched only once every answer is in hand.

## 1. Intake dialogue (you, in the main thread)

Ask via `AskUserQuestion`, one question at a time. Validate each answer before
moving on and re-ask on a violation:

| Ask for | Constraint |
| - | - |
| Server name | `^[a-zA-Z0-9_-]+$` |
| Host (LAN IP, hostname or WAN domain) | `^[a-zA-Z0-9.-]+$` |
| SSH port | 1–65535, default 22 |
| SSH user | `^[a-zA-Z0-9_.-]+$` |
| Description | free text, optional, multiword allowed |
| Authorized scopes (multi-select) | any of `system_monitoring`, `file_operations`, `package_management`, `service_management`, `docker_compose`, `file_transfer` |

Offer scopes as an explicit multi-select. Do not preselect them all — each one
widens what later commands may do without asking again.

## 2. Dispatch the agent

Use Claude's native **Task tool** (NOT a bash command — do not write `Task(...)`
in a script) to invoke the subagent named `fleet-intake` (Claude Code resolves
plugin agents by their frontmatter `name`), passing every collected value:

> Onboard this server into the fleet-manager workspace. It is non-interactive:
> all inputs are below, and you have no way to ask for more.
> name=<name> host=<host> port=<port> user=<user>
> description=<description>
> scopes=<comma-separated list>
> set_active=yes
> Write the Connection section, ensure the plugin keypair exists, cold-test the
> connection, then run discovery, apply exactly these scopes, and regenerate
> inventory.md. If the cold test fails, return NEEDS_KEY_DEPLOY with the exact
> ssh-copy-id line and stop.

## 3. Handle the agent's return value

- **Summary** → relay it to the user and suggest `/diag`, `/status`, `/list-servers`.
- **`NEEDS_KEY_DEPLOY: <name>`** → the profile is already written. Present the
  `! ssh-copy-id …` line the agent returned as copy-paste text, with the leading
  `!` so it runs in the user's session — never run it yourself, it needs a TTY.
  If the agent flagged a missing host key, present the `ssh-keyscan` line too and
  tell the user to review the fingerprint first. Then ask via `AskUserQuestion`
  whether the deployment went through, and on confirmation re-dispatch the agent
  with the identical inputs; it resumes at the connectivity test.
- **`NEEDS_INPUT: <reason>`** → resolve it with the user and re-dispatch.
- **`FAILED: <cause>`** → relay the cause and the three common reasons; ask
  whether to retry the key step.
