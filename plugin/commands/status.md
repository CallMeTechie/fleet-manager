---
description: System status snapshot for a server — disk, memory, uptime, CPU cores and load.
allowed-tools: Bash, Read, Write, Edit
---

# Status

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"

NAME="$(resolve_server "$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')")"
build_ssh "$NAME"
echo_target "$NAME"

# Each query is guarded so one failing SSH call does not abort the rest under
# `set -e` (C1). A helper keeps it DRY.
fm_show() { # <heading> <remote-cmd>
  echo "── $1 ──"
  "${FM_SSH[@]}" "$2" 2>/dev/null || echo "(query failed — transient SSH error?)"
}
fm_show "Disk"        "df -h"
fm_show "Memory"      "free -h"
fm_show "Uptime/Load" "uptime"
fm_show "CPU"         "nproc 2>/dev/null || getconf _NPROCESSORS_ONLN"
```

After printing, refresh the **Discovered State** section and the UTC **Last Updated**
line of `context/servers/<name>.md`.
