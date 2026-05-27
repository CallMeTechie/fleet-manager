---
description: List all servers in the fleet-manager inventory and mark the active one. Regenerates inventory.md.
allowed-tools: Bash, Read
---

# List servers

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"

if [ -z "$(list_server_names)" ]; then
  echo "Inventory is empty. Run /first-run to onboard your first server."
  exit 0
fi

write_inventory
cat "$FM_CONTEXT/inventory.md"
```

Display the table to the user. The `*` in the Active column marks the active server.
