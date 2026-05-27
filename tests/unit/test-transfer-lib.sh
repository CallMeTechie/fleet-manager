#!/usr/bin/env bash
# Unit tests for _transfer-lib.sh — pure functions, no network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$ROOT/plugin/commands/_transfer-lib.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
no()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
assert_eq()   { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want='$2' got='$1')"; fi; }
assert_ok()   { if "$@" >/dev/null 2>&1; then ok "ok: $*"; else no "expected success: $*"; fi; }
assert_fail() { if "$@" >/dev/null 2>&1; then no "expected failure: $*"; else ok "fails: $*"; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export FM_CONTEXT_DIR="$TMP"; mkdir -p "$TMP/servers"
# shellcheck source=/dev/null
source "$LIB"

cat > "$TMP/servers/web.md" <<'EOF'
## Connection
- host: 1.2.3.4
- port: 22
- user: deploy
- key_path: ~/.ssh/k
- connect_timeout_seconds: 10
## Protected Resources
- protected_paths: /var/www, /srv/data
EOF

# parse_endpoint
parse_endpoint "web:/srv/x"; assert_eq "$FM_EP_KIND" "remote" "remote kind"
assert_eq "$FM_EP_SERVER" "web" "remote server"; assert_eq "$FM_EP_PATH" "/srv/x" "remote path"
parse_endpoint "./local";    assert_eq "$FM_EP_KIND" "local" "local kind"
parse_endpoint "/tmp/a:b";   assert_eq "$FM_EP_KIND" "local" "colon-in-local stays local"
parse_endpoint "web:";       assert_eq "$FM_EP_PATH" "" "empty remote path = home"

# is_protected_path (boundary-safe)
assert_ok   is_protected_path web /var/www
assert_ok   is_protected_path web /var/www/site/index.html
assert_fail is_protected_path web /var/wwwbackup
assert_fail is_protected_path web /home/deploy
cat > "$TMP/servers/nop.md" <<'EOF'
## Protected Resources
- protected_paths:
EOF
assert_fail is_protected_path nop /anything

# build_rsync_rsh
build_rsync_rsh web
case "$FM_RSYNC_RSH" in *"-i $HOME/.ssh/k"*"-p 22"*) ok "rsync_rsh has key+port";; *) no "rsync_rsh: $FM_RSYNC_RSH";; esac
assert_eq "$FM_REMOTE" "deploy@1.2.3.4" "FM_REMOTE"

# local_has_rsync runs cleanly either way
if local_has_rsync; then ok "local_has_rsync: present"; else ok "local_has_rsync: absent (ok either way)"; fi

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
