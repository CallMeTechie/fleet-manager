#!/usr/bin/env bash
# Unit test for server_health_line — parse/format/validate only (no network).
# Lives in its own file so it can override build_ssh without colliding with the
# real build_ssh calls in test-fleet-lib.sh (which would trip SC2218).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$ROOT/plugin/commands/_fleet-lib.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export FM_CONTEXT_DIR="$TMP"; mkdir -p "$TMP/servers"
# shellcheck source=/dev/null
source "$LIB"

# Fake remote endpoints, invoked indirectly via the FM_SSH array.
# shellcheck disable=SC2317
_fake_up()  { printf '%s\n' 'Debian 12|41%|0.12|58%|host1'; }
# shellcheck disable=SC2317
_fake_bad() { printf '%s\n' 'a|b|c'; }

cat > "$TMP/servers/mon.md" <<'EOF'
## Connection
- host: 1.2.3.4
- port: 22
- user: deploy
- key_path: ~/.ssh/k
- connect_timeout_seconds: 5
## Identity
- docker_available: yes
## Scoped Operations
- [x] system_monitoring
EOF

# UP: build_ssh override points FM_SSH at the canned-line function (ignores snippet arg).
# shellcheck disable=SC2317,SC2034  # build_ssh is invoked by server_health_line; FM_SSH consumed there
build_ssh() { FM_SSH=(_fake_up); }
row="$(server_health_line mon mon)"
case "$row" in *"UP"*"Debian 12"*"41%"*) ok "health UP row parses";; *) no "health row: $row";; esac

# malformed (3 fields) -> DOWN
# shellcheck disable=SC2317,SC2034
build_ssh() { FM_SSH=(_fake_bad); }
row="$(server_health_line mon mon)"
case "$row" in *DOWN*) ok "malformed -> DOWN";; *) no "malformed: $row";; esac

# scope off -> SKIP (build_ssh not even reached)
cat > "$TMP/servers/noscope.md" <<'EOF'
## Connection
- host: 1.2.3.4
- port: 22
- user: deploy
- key_path: ~/.ssh/k
- connect_timeout_seconds: 5
## Scoped Operations
- [ ] system_monitoring
EOF
row="$(server_health_line noscope noscope)"
case "$row" in *SKIP*) ok "scope off -> SKIP";; *) no "skip: $row";; esac

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
