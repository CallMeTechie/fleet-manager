#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib/test-helpers.sh"
it_boot yes nopasswd
export FM_CONTEXT_DIR="$WORK/context"
export FM_SSH_EXTRA_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# shellcheck source=/dev/null
source "$ROOT/plugin/commands/_fleet-lib.sh"
mkdir -p "$WORK/context/servers"
# 'up' points at the mock, system_monitoring on
cat > "$WORK/context/servers/up.md" <<EOF
## Connection
- host: 127.0.0.1
- port: $SSH_PORT
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 5
## Identity
- docker_available: yes
## Scoped Operations
- [x] system_monitoring
EOF
# 'down' is a dead port
cat > "$WORK/context/servers/down.md" <<EOF
## Connection
- host: 127.0.0.1
- port: 59999
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 2
## Scoped Operations
- [x] system_monitoring
EOF
# 'noscope' has system_monitoring off
cat > "$WORK/context/servers/noscope.md" <<EOF
## Connection
- host: 127.0.0.1
- port: $SSH_PORT
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 5
## Scoped Operations
- [ ] system_monitoring
EOF
r_up="$(server_health_line up up)";       case "$r_up" in *UP*) it_ok "mock server UP";; *) it_no "up: $r_up";; esac
r_dn="$(server_health_line down up)";     case "$r_dn" in *DOWN*) it_ok "dead port DOWN";; *) it_no "down: $r_dn";; esac
r_sk="$(server_health_line noscope up)";  case "$r_sk" in *SKIP*) it_ok "noscope SKIP";; *) it_no "skip: $r_sk";; esac
echo "health-summary: PASS=$IT_PASS FAIL=$IT_FAIL"; [ "$IT_FAIL" -eq 0 ]
