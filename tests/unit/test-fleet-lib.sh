#!/usr/bin/env bash
# Unit tests for _fleet-lib.sh — pure functions, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$ROOT/plugin/commands/_fleet-lib.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
no()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
assert_eq()   { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want='$2' got='$1')"; fi; }
assert_grep() { if grep -q "$1" "$2"; then ok "$3"; else no "$3"; fi; }
assert_ok()   { if "$@" >/dev/null 2>&1; then ok "ok: $*"; else no "expected success: $*"; fi; }
assert_fail() { if "$@" >/dev/null 2>&1; then no "expected failure: $*"; else ok "fails: $*"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export FM_CONTEXT_DIR="$TMP"
mkdir -p "$TMP/servers"

# shellcheck source=/dev/null
source "$LIB"

# --- validate_server_name ---
assert_ok   validate_server_name "web-01"
assert_ok   validate_server_name "prod_db"
assert_fail validate_server_name "../etc"
assert_fail validate_server_name "has space"

# --- sanitize_value (H4: the CR-stripping is the whole point of the function) ---
assert_eq "$(sanitize_value $'  1.2.3.4\r')" "1.2.3.4" "sanitize strips CR + surrounding space"
assert_eq "$(sanitize_value $'\tDebian 12  ')" "Debian 12" "sanitize trims tabs/spaces, keeps inner"

# --- strict_field / text_field ---
cat > "$TMP/servers/web.md" <<'EOF'
# Server: web
## Connection
- host: 1.2.3.4
- port: 22
- user: deploy
- key_path: ~/.ssh/fleet-manager_ed25519
- connect_timeout_seconds: 10
## Identity
- description: Hetzner VPS, callmetechie.de
- os: Debian GNU/Linux 12
- hostname: _not configured_
EOF

assert_eq "$(strict_field "$TMP/servers/web.md" host)" "1.2.3.4" "strict host"
assert_eq "$(strict_field "$TMP/servers/web.md" port)" "22"      "strict port"
assert_eq "$(strict_field "$TMP/servers/web.md" user)" "deploy"  "strict user"
assert_fail strict_field "$TMP/servers/web.md" description
assert_fail strict_field "$TMP/servers/web.md" nonexistent
assert_eq "$(text_field "$TMP/servers/web.md" description)" "Hetzner VPS, callmetechie.de" "text desc"
assert_eq "$(text_field "$TMP/servers/web.md" os)" "Debian GNU/Linux 12" "text os (slashes)"
assert_eq "$(text_field "$TMP/servers/web.md" hostname)" "" "text placeholder -> empty"

# --- load_profile + build_ssh ---
assert_ok load_profile web
assert_eq "$FM_HOST" "1.2.3.4" "load FM_HOST"
assert_eq "$FM_PORT" "22"      "load FM_PORT"
assert_eq "$FM_USER" "deploy"  "load FM_USER"
assert_eq "$FM_KEY_PATH" "$HOME/.ssh/fleet-manager_ed25519" "tilde expanded to HOME"

# invalid host rejected — multiword (caught by strict_field)
cat > "$TMP/servers/bad.md" <<'EOF'
## Connection
- host: bad host!
- port: 22
- user: x
- key_path: ~/.ssh/k
- connect_timeout_seconds: 10
EOF
assert_fail load_profile bad

# invalid host rejected — SINGLE-token but regex-violating (must hit the
# load_profile regex, NOT strict_field's multiword check). Covers the otherwise
# untested host/user regex path (reviewer H2).
cat > "$TMP/servers/evil.md" <<'EOF'
## Connection
- host: a;b|c
- port: 22
- user: root
- key_path: ~/.ssh/k
- connect_timeout_seconds: 10
EOF
assert_fail load_profile evil
# and a bad port (non-numeric, single token)
cat > "$TMP/servers/badport.md" <<'EOF'
## Connection
- host: 1.2.3.4
- port: 99999
- user: root
- key_path: ~/.ssh/k
- connect_timeout_seconds: 10
EOF
assert_fail load_profile badport

build_ssh web
assert_eq "${FM_SSH[0]}" "ssh" "build_ssh[0]"
assert_eq "${FM_SSH[*]: -1}" "deploy@1.2.3.4" "build_ssh last = user@host"
# key path is expanded inside the array
if printf '%s\n' "${FM_SSH[@]}" | grep -q "$HOME/.ssh/fleet-manager_ed25519"; then
  ok "build_ssh uses expanded key"
else
  no "build_ssh key not expanded"
fi

# --- resolve_server / set_active / list / inventory ---
assert_fail resolve_server ""                 # no active, no arg
assert_eq "$(resolve_server web)" "web" "resolve explicit arg"
assert_fail resolve_server ghost              # unknown server

assert_ok set_active web
assert_eq "$(cat "$TMP/active-server")" "web" "active-server written"
assert_eq "$(resolve_server)" "web" "resolve from active-server"
assert_fail set_active ghost                  # cannot activate unknown

# second server for inventory
cat > "$TMP/servers/db.md" <<'EOF'
## Connection
- host: 10.0.0.9
- port: 22
- user: root
- key_path: ~/.ssh/fleet-manager_ed25519
- connect_timeout_seconds: 10
## Identity
- description: Postgres box
EOF
names="$(list_server_names | sort | tr '\n' ',')"
# Profiles created so far: web, bad, evil, badport (above) + db (here).
assert_eq "$names" "bad,badport,db,evil,web," "list_server_names finds all (templates excluded by glob)"

write_inventory
assert_grep "| \* | web |" "$TMP/inventory.md" "inventory marks active web"
assert_grep "Postgres box" "$TMP/inventory.md" "inventory shows db description"

# --- profile_exists (re-add protection basis, H3) ---
assert_ok   profile_exists web
assert_fail profile_exists ghost
assert_fail profile_exists "../etc"   # traversal name rejected before path check

# --- build_ssh FM_SSH_EXTRA_OPTS seam ---
FM_SSH_EXTRA_OPTS="-o StrictHostKeyChecking=no" build_ssh web
if printf '%s\n' "${FM_SSH[@]}" | grep -q "StrictHostKeyChecking=no"; then ok "extra opts spliced"; else no "extra opts not spliced"; fi
unset FM_SSH_EXTRA_OPTS
build_ssh web   # restore plain FM_SSH for any later use

# --- Phase 2 gates ---
cat > "$TMP/servers/gated.md" <<'EOF'
# Server: gated
## Connection
- host: 1.2.3.4
- port: 22
- user: deploy
- key_path: ~/.ssh/k
- connect_timeout_seconds: 10
## Scoped Operations
- [x] system_monitoring
- [ ] docker_compose
## Protected Resources
- critical_compose_projects: mailpilot, gatecontrol-gateway
- protected_paths: /var/www/site
EOF

assert_ok   is_scope_authorized gated system_monitoring
assert_fail is_scope_authorized gated docker_compose
assert_fail is_scope_authorized gated nonexistent_scope

assert_ok   is_protected_resource gated compose_project mailpilot
assert_ok   is_protected_resource gated compose_project gatecontrol-gateway
assert_fail is_protected_resource gated compose_project other
assert_ok   is_protected_resource gated path /var/www/site
assert_fail is_protected_resource gated path /etc/passwd

assert_ok   confirm_destructive mailpilot mailpilot
assert_fail confirm_destructive mailpilot wrongname
assert_fail confirm_destructive mailpilot ""
FM_CONFIRM_CRITICAL=yes assert_ok confirm_destructive mailpilot ""

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
