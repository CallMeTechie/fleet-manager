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
cf="$(compose_find_project web | jq -r '.ConfigFiles')"
args="$(compose_config_args "$cf")"
# shellcheck disable=SC2086
if "${FM_SSH[@]}" "$FM_DOCKER compose $args logs --tail 10" | grep -q "listening"; then it_ok "compose logs"; else it_no "logs"; fi
echo "compose-logs: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
