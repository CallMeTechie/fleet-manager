#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_compose-lib.sh"
it_make_compose_profile web; build_ssh web; it_ssh_insecure; resolve_docker_cmd web
if "${FM_SSH[@]}" "$FM_DOCKER ps --format '{{.Names}}'" | grep -q web-app-1; then it_ok "docker ps rows"; else it_no "ps"; fi
echo "docker-list: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
