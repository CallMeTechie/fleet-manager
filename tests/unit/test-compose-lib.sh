#!/usr/bin/env bash
# Unit tests for _compose-lib.sh — pure functions, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$ROOT/plugin/commands/_compose-lib.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
no()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
assert_eq()   { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want='$2' got='$1')"; fi; }
assert_ok()   { if "$@" >/dev/null 2>&1; then ok "ok: $*"; else no "expected success: $*"; fi; }
assert_fail() { if "$@" >/dev/null 2>&1; then no "expected failure: $*"; else ok "fails: $*"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export FM_CONTEXT_DIR="$TMP"
mkdir -p "$TMP/servers"
# shellcheck source=/dev/null
source "$LIB"

# --- resolve_docker_cmd ---
cat > "$TMP/servers/ok.md" <<'EOF'
## Connection
- host: 1.2.3.4
- port: 22
- user: deploy
- key_path: ~/.ssh/k
- connect_timeout_seconds: 10
## Identity
- docker_available: yes
- docker_cmd: sudo -n docker
EOF
assert_ok resolve_docker_cmd ok
assert_eq "$FM_DOCKER" "sudo -n docker" "resolve_docker_cmd sets FM_DOCKER"

cat > "$TMP/servers/evil.md" <<'EOF'
## Identity
- docker_available: yes
- docker_cmd: docker; rm -rf /
EOF
assert_fail resolve_docker_cmd evil          # allowlist violation

cat > "$TMP/servers/nodocker.md" <<'EOF'
## Identity
- docker_available: no
- docker_cmd: _not configured_
EOF
assert_fail resolve_docker_cmd nodocker

# --- compose_config_args ---
assert_eq "$(compose_config_args /vol/a.yml)" "-f /vol/a.yml" "single file"
assert_eq "$(compose_config_args /vol/a.yml,/vol/b.override.yaml)" "-f /vol/a.yml -f /vol/b.override.yaml" "multi-file split"
assert_fail compose_config_args ""                 # empty -> error
assert_fail compose_config_args "null"             # null -> error
assert_fail compose_config_args "/vol/a.yml; rm"   # invalid path -> error

# --- compose_find_project (against sample JSON via a stubbed compose_ls_json) ---
compose_ls_json() { cat "$TMP/sample.json"; }
cat > "$TMP/sample.json" <<'EOF'
[{"Name":"web","Status":"running(2)","ConfigFiles":"/vol/web/docker-compose.yml"},
 {"Name":"db","Status":"exited(0)","ConfigFiles":"/vol/db/a.yml,/vol/db/b.override.yml"},
 {"Name":"new","Status":"created(0)","ConfigFiles":"/vol/new/compose.yaml"}]
EOF
assert_eq "$(compose_find_project web | jq -r '.Status')" "running(2)" "find running project"
assert_eq "$(compose_find_project db | jq -r '.ConfigFiles')" "/vol/db/a.yml,/vol/db/b.override.yml" "find multi-file project"
assert_eq "$(compose_find_project ghost)" "" "missing project -> empty"

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
