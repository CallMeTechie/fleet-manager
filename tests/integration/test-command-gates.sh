#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd

# web: scope ticked, db critical. noscope: docker_compose unticked.
it_make_compose_profile web "- [x] docker_compose" "db"
it_make_compose_profile noscope "- [ ] docker_compose"

# 1. scope refusal — /compose-up against noscope must exit non-zero
if it_run_command compose-up.md "noscope web" >/dev/null 2>&1; then it_no "compose-up should refuse unticked scope"; else it_ok "compose-up refuses unticked scope (body)"; fi

# 2. critical project WITHOUT token — /compose-down web db must refuse
if it_run_command compose-down.md "web db" >/dev/null 2>&1; then it_no "compose-down critical w/o token should refuse"; else it_ok "compose-down refuses critical w/o token (body)"; fi

# 3. critical project WITH matching token — proceeds (stub returns success)
if it_run_command compose-down.md "web db --confirm=db" >/dev/null 2>&1; then it_ok "compose-down proceeds with matching token (body)"; else it_no "compose-down should proceed with token"; fi

# 4. wrong token — must still refuse
if it_run_command compose-down.md "web db --confirm=wrong" >/dev/null 2>&1; then it_no "wrong token should refuse"; else it_ok "compose-down refuses wrong token (body)"; fi

# 5. non-critical project (web) — proceeds without token
if it_run_command compose-down.md "web web" >/dev/null 2>&1; then it_ok "compose-down non-critical proceeds (body)"; else it_no "non-critical should proceed"; fi

# 6. not-yet-indexed project — /compose-up errors with --file hint
out="$(it_run_command compose-up.md "web ghostproj" 2>&1 || true)"
case "$out" in *"--file"*) it_ok "compose-up hints --file for unindexed (body)";; *) it_no "compose-up --file hint missing: $out";; esac

echo "command-gates: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
