---
description: One-line health row per server across the whole fleet (sequential). UP/DOWN/SKIP + verdict.
allowed-tools: Bash, Read
---

# Health Summary

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"

names="$(list_server_names)"
[ -n "$names" ] || { echo "Inventory empty — run /first-run."; exit 0; }

active=""; [ -f "$FM_ACTIVE_FILE" ] && active="$(tr -d '[:space:]' < "$FM_ACTIVE_FILE")"

printf '%s%-13s %-7s %-15s %-6s %-6s %-6s %s\n' "  " "SERVER" "STATUS" "OS" "DISK/" "LOAD" "MEM" "DOCKER"
up=0; total=0; skipped=0
while IFS= read -r n; do
  [ -n "$n" ] || continue
  total=$((total+1))
  # if-let captures the 0/1/2 return AND prevents set -e from aborting on DOWN/SKIP;
  # a bare `if…fi` followed by `rc=$?` would always be 0.
  if row="$(server_health_line "$n" "$active")"; then rc=0; else rc=$?; fi
  case "$rc" in 0) up=$((up+1)) ;; 2) skipped=$((skipped+1)) ;; esac
  printf '%s\n' "$row"
done <<< "$names"

echo "Verdict: $up/$total up"
if [ "$skipped" -eq "$total" ] && [ "$total" -gt 0 ]; then
  echo "(All servers SKIP — tick 'system_monitoring' in the profiles to enable health checks.)"
fi
```
