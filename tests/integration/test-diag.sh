#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"

run_diag() { # <mock_docker> <mock_sudo>
  local sudo_state docker_state
  it_boot "$1" "$2"
  it_lib; it_make_profile web; build_ssh web; it_ssh_insecure
  if "${FM_SSH[@]}" "echo OK" 2>/dev/null | grep -qx OK; then it_ok "[$1/$2] ssh reachable"; else it_no "[$1/$2] ssh"; fi
  if "${FM_SSH[@]}" "sudo -n true 2>/dev/null"; then sudo_state=yes; else sudo_state=no; fi
  if "${FM_SSH[@]}" "command -v docker >/dev/null 2>&1"; then docker_state=yes; else docker_state=no; fi
  if [ "$docker_state" = "$1" ]; then it_ok "[$1/$2] docker presence matches toggle"; else it_no "[$1/$2] docker=$docker_state"; fi
  case "$2" in
    nopasswd) if [ "$sudo_state" = yes ]; then it_ok "[$1/$2] sudo nopasswd"; else it_no "[$1/$2] sudo=$sudo_state"; fi ;;
    passwd)   if [ "$sudo_state" = no  ]; then it_ok "[$1/$2] sudo requires pw"; else it_no "[$1/$2] sudo=$sudo_state"; fi ;;
  esac
  it_cleanup
}

run_diag yes nopasswd
run_diag no  passwd

echo "diag: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
