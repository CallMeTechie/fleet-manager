---
description: Onboard your first server into fleet-manager via the interactive intake agent.
allowed-tools: Bash, Read, Write, Edit, Task
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
echo "No servers yet — launching the intake agent."
```

If the inventory is empty, use Claude's native **Task tool** (NOT a bash command —
do not write `Task(...)` in a script) to invoke the subagent named `fleet-intake`
(Claude Code resolves plugin agents by their frontmatter `name`) with this instruction:

> Onboard the user's first server into the fleet-manager workspace. Gather
> connection details, write the profile's Connection section, deploy the plugin
> SSH key (`/setup-ssh` flow — present `! ssh-copy-id …` as copy-paste, never run
> it yourself), run discovery, capture authorized scopes, write the full profile,
> set it active, and regenerate inventory.md.
> Be conversational and ask one question at a time.
