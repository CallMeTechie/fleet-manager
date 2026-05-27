#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
mkdir -p "$WORK/context/servers"
cat > "$WORK/context/servers/web.md" <<EOF
## Connection
- host: 127.0.0.1
- port: $SSH_PORT
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 5
## Scoped Operations
- [x] file_transfer
## Protected Resources
- protected_paths: /tmp/prot
EOF
echo "hello-fleet" > "$WORK/up.txt"
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_fleet-lib.sh"; build_ssh web; it_ssh_insecure
"${FM_SSH[@]}" "mkdir -p /tmp/prot"
# upload — success required: assert it ran AND landed.
if it_run_command copy.md "$WORK/up.txt web:/tmp/up.txt" >/dev/null 2>&1; then it_ok "upload command exited 0"; else it_no "upload command failed"; fi
if "${FM_SSH[@]}" "cat /tmp/up.txt" | grep -q hello-fleet; then it_ok "upload landed on mock"; else it_no "upload effect"; fi
# download
mkdir -p "$WORK/dl"
if it_run_command copy.md "web:/tmp/up.txt $WORK/dl/" >/dev/null 2>&1; then it_ok "download command exited 0"; else it_no "download command failed"; fi
if grep -q hello-fleet "$WORK/dl/up.txt" 2>/dev/null; then it_ok "download to local"; else it_no "download effect"; fi
# protected dest WITHOUT token -> refused (no file written)
if it_run_command copy.md "$WORK/up.txt web:/tmp/prot/up.txt" >/dev/null 2>&1; then it_no "protected dest should refuse"; else it_ok "protected dest refused w/o token"; fi
if "${FM_SSH[@]}" "test -e /tmp/prot/up.txt"; then it_no "protected file wrongly written"; else it_ok "protected file absent after refusal"; fi
# protected dest WITH matching token -> proceeds + lands
if it_run_command copy.md "$WORK/up.txt web:/tmp/prot/up.txt --confirm=web" >/dev/null 2>&1; then it_ok "protected dest proceeds with token"; else it_no "protected w/ token failed"; fi
if "${FM_SSH[@]}" "cat /tmp/prot/up.txt" | grep -q hello-fleet; then it_ok "protected file landed with token"; else it_no "protected effect"; fi
echo "copy: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
