#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_compose-lib.sh"
it_make_compose_profile noscope "- [ ] docker_compose"
if is_scope_authorized noscope docker_compose; then it_no "should refuse unticked scope"; else it_ok "scope refused when unticked"; fi
it_make_compose_profile web
build_ssh web; it_ssh_insecure; resolve_docker_cmd web
if [ -n "$(compose_find_project web)" ]; then it_ok "indexed project found"; else it_no "web find"; fi
if [ -z "$(compose_find_project ghost)" ]; then it_ok "ghost not indexed (would hint --file)"; else it_no "ghost"; fi
echo "compose-up: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
