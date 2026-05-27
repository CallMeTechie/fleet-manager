#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
mkdir -p "$WORK/context/servers" "$WORK/srcdir"
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
- protected_paths:
EOF
# a second profile whose dest IS a protected path
cat > "$WORK/context/servers/webp.md" <<EOF
## Connection
- host: 127.0.0.1
- port: $SSH_PORT
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 5
## Scoped Operations
- [x] file_transfer
## Protected Resources
- protected_paths: /tmp/synctest
EOF
echo "a" > "$WORK/srcdir/a.txt"
export FM_CONTEXT_DIR="$WORK/context"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_fleet-lib.sh"; build_ssh web; it_ssh_insecure
"${FM_SSH[@]}" "rm -rf /tmp/synctest && mkdir -p /tmp/synctest"

# dry-run: positive signal (banner) AND no remote change
out="$(it_run_command sync.md "$WORK/srcdir/ web:/tmp/synctest/" 2>&1 || true)"
case "$out" in *"DRY RUN"*) it_ok "dry-run printed banner";; *) it_no "no DRY RUN banner: $out";; esac
n="$("${FM_SSH[@]}" "ls /tmp/synctest | wc -l" | tr -d '[:space:]')"
if [ "$n" = "0" ]; then it_ok "dry-run made no change"; else it_no "dry-run changed remote ($n)"; fi

# apply: mirrors
if it_run_command sync.md "$WORK/srcdir/ web:/tmp/synctest/ --apply" >/dev/null 2>&1; then it_ok "apply exited 0"; else it_no "apply failed"; fi
if "${FM_SSH[@]}" "cat /tmp/synctest/a.txt" | grep -q a; then it_ok "apply mirrored file"; else it_no "apply effect"; fi

# remote-only orphan that --delete must remove
"${FM_SSH[@]}" "touch /tmp/synctest/orphan"
if it_run_command sync.md "$WORK/srcdir/ web:/tmp/synctest/ --apply --delete" >/dev/null 2>&1; then it_no "delete w/o token should refuse"; else it_ok "delete refused w/o confirm-delete"; fi
if "${FM_SSH[@]}" "test -e /tmp/synctest/orphan"; then it_ok "orphan kept (delete refused)"; else it_no "orphan wrongly deleted"; fi
it_run_command sync.md "$WORK/srcdir/ web:/tmp/synctest/ --apply --delete --confirm-delete=web" >/dev/null 2>&1 || true
if "${FM_SSH[@]}" "test -e /tmp/synctest/orphan"; then it_no "orphan should be deleted"; else it_ok "orphan removed with confirm-delete"; fi

# protected-path destination + delete needs --confirm=<server> IN ADDITION
if it_run_command sync.md "$WORK/srcdir/ webp:/tmp/synctest/ --apply --delete --confirm-delete=webp" >/dev/null 2>&1; then it_no "protected+delete should refuse w/o --confirm"; else it_ok "protected+delete refused w/o --confirm=webp"; fi
echo "sync: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
