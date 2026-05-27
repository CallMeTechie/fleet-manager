#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
it_lib; it_make_profile web; build_ssh web; it_ssh_insecure

if "${FM_SSH[@]}" "df -h"   | grep -q '/';     then it_ok "df output";     else it_no "df";     fi
if "${FM_SSH[@]}" "free -h" | grep -qi 'mem';  then it_ok "free output";   else it_no "free";   fi
if "${FM_SSH[@]}" "uptime"  | grep -qi 'load'; then it_ok "uptime output"; else it_no "uptime"; fi
if "${FM_SSH[@]}" "nproc 2>/dev/null || getconf _NPROCESSORS_ONLN" | grep -qE '^[0-9]+$'; then it_ok "nproc"; else it_no "nproc"; fi

echo "status: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
