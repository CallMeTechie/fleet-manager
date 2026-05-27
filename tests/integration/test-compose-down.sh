#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_compose-lib.sh"
# db is critical
it_make_compose_profile web "- [x] docker_compose" "db"
build_ssh web; it_ssh_insecure; resolve_docker_cmd web

if is_scope_authorized web docker_compose; then it_ok "scope ok"; else it_no "scope"; fi
if is_protected_resource web compose_project db; then it_ok "db is critical"; else it_no "db critical"; fi
if confirm_destructive db "" 2>/dev/null; then it_no "should refuse no token"; else it_ok "refuse without token"; fi
if confirm_destructive db db 2>/dev/null; then it_ok "allow matching token"; else it_no "matching token"; fi
if is_protected_resource web compose_project web; then it_no "web should not be critical"; else it_ok "web not critical"; fi
echo "compose-down: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
