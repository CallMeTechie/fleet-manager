#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_lib
it_make_profile web
it_make_profile db

if [ "$(resolve_server web)" = "web" ]; then it_ok "resolve override web"; else it_no "resolve override"; fi
set_active db
if [ "$(resolve_server)" = "db" ]; then it_ok "resolve active db"; else it_no "resolve active"; fi
if [ "$(resolve_server web)" = "web" ]; then it_ok "override beats active"; else it_no "override beats active"; fi
if resolve_server ghost >/dev/null 2>&1; then it_no "ghost should fail"; else it_ok "unknown server errors"; fi

build_ssh db; out="$(echo_target db)"
case "$out" in *"deploy@127.0.0.1:$SSH_PORT"*) it_ok "echo_target shows target";; *) it_no "echo_target: $out";; esac

echo "resolve: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
