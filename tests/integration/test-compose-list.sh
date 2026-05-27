#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_compose-lib.sh"
it_make_compose_profile web
build_ssh web; it_ssh_insecure
resolve_docker_cmd web
out="$(compose_ls_json)"
if echo "$out" | jq -e '.[] | select(.Name=="db")' >/dev/null; then it_ok "compose ls returns db"; else it_no "compose ls"; fi
cf="$(compose_find_project db | jq -r '.ConfigFiles')"
if [ "$(compose_config_args "$cf")" = "-f /srv/db/docker-compose.yml -f /srv/db/docker-compose.override.yml" ]; then it_ok "multi-file -f args"; else it_no "multi-file: $(compose_config_args "$cf")"; fi
# Empty ConfigFiles row must hard-abort end-to-end (review H2).
bcf="$(compose_find_project broken | jq -r '.ConfigFiles')"
if compose_config_args "$bcf" >/dev/null 2>&1; then it_no "empty ConfigFiles should abort"; else it_ok "empty ConfigFiles aborts (broken row)"; fi
echo "compose-list: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
