#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_fleet-lib.sh"
it_make_compose_profile web; build_ssh web; it_ssh_insecure
if is_scope_authorized web system_monitoring; then it_ok "logs scope ok"; else it_no "scope"; fi
if "${FM_SSH[@]}" "command -v journalctl >/dev/null 2>&1 && journalctl -n 5 --no-pager" | grep -q "mock"; then it_ok "journalctl stub"; else it_no "journalctl"; fi
# Empty-unit hint path (review M3): unknown unit -> hint to /compose-logs.
out_logs="$(it_run_command logs.md "web doesnotexist" || true)"
case "$out_logs" in *"/compose-logs"*) it_ok "logs hints /compose-logs for unknown unit";; *) it_no "logs hint missing: $out_logs";; esac
echo "logs: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
