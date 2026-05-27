#!/usr/bin/env bash
# Helpers shared by integration tests. Sourced.
# shellcheck shell=bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export ROOT
IMG="fleet-manager-mock:test"
CTR="fleet-mock-$$"
WORK="$(mktemp -d)"
SSH_PORT=22022

it_cleanup() { docker rm -f "$CTR" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap it_cleanup EXIT

it_boot() {
  local mock_docker="${1:-yes}" mock_sudo="${2:-nopasswd}"
  docker build -q -t "$IMG" "$ROOT/tests/fixtures/mock-server" >/dev/null
  mkdir -p "$WORK/keys" "$WORK/context/servers"
  ssh-keygen -t ed25519 -N "" -f "$WORK/keys/fleet-manager_ed25519" -C test >/dev/null
  docker run -d --name "$CTR" -p "$SSH_PORT:22" \
    -e MOCK_DOCKER="$mock_docker" -e MOCK_SUDO="$mock_sudo" \
    -e FLEET_PUBKEY="$(cat "$WORK/keys/fleet-manager_ed25519.pub")" "$IMG" >/dev/null
  # wait for sshd ( _ = intentionally unused loop counter)
  for _ in $(seq 1 30); do
    if ssh -i "$WORK/keys/fleet-manager_ed25519" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 -p "$SSH_PORT" \
        deploy@127.0.0.1 "echo ready" 2>/dev/null | grep -qx ready; then
      return 0
    fi
    sleep 1
  done
  echo "mock server did not become ready" >&2; return 1
}

it_make_profile() {
  local name="$1"
  mkdir -p "$WORK/context/servers"   # callers that skip it_boot (e.g. test-resolve) still need this
  cat > "$WORK/context/servers/$name.md" <<EOF
# Server: $name
## Connection
- host: 127.0.0.1
- port: $SSH_PORT
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 5
## Identity
- description: mock $name
EOF
}

it_lib() {
  export FM_CONTEXT_DIR="$WORK/context"
  # shellcheck source=/dev/null
  source "$ROOT/plugin/commands/_fleet-lib.sh"
}

# Append known-hosts-bypass flags to the FM_SSH array for tests only.
it_ssh_insecure() {
  FM_SSH=( "${FM_SSH[@]:0:1}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${FM_SSH[@]:1}" )
}

IT_PASS=0; IT_FAIL=0
it_ok() { IT_PASS=$((IT_PASS+1)); echo "ok   - $1"; }
it_no() { IT_FAIL=$((IT_FAIL+1)); echo "FAIL - $1"; }

# it_make_compose_profile <name> [scope_line] [critical_list] — profile with docker_cmd + scopes.
it_make_compose_profile() {
  local name="$1" scope="${2:-- [x] docker_compose}" crit="${3:-}"
  mkdir -p "$WORK/context/servers"
  cat > "$WORK/context/servers/$name.md" <<EOF
# Server: $name
## Connection
- host: 127.0.0.1
- port: $SSH_PORT
- user: deploy
- key_path: $WORK/keys/fleet-manager_ed25519
- connect_timeout_seconds: 5
## Identity
- docker_available: yes
- docker_cmd: docker
## Scoped Operations
$scope
- [x] system_monitoring
## Protected Resources
- critical_compose_projects: $crit
- protected_paths:
EOF
}

# it_run_command <command-file.md> <arguments> — extract the FIRST bash block from a
# command markdown and run it with plugin env + ARGUMENTS against the mock (relaxed host
# keys via FM_SSH_EXTRA_OPTS). Echoes output; returns the command's exit code. Exercises
# the arg-parsing + gate ORDERING that lives in the .md body (review C3).
it_run_command() {
  local md="$1" args="$2" block
  block="$(mktemp "$WORK/cmd.XXXXXX.sh")"
  awk '/^```bash$/{f=1;next} /^```$/{if(f){exit}} f{print}' "$ROOT/plugin/commands/$md" > "$block"
  CLAUDE_PLUGIN_ROOT="$ROOT/plugin" \
  FM_CONTEXT_DIR="$WORK/context" \
  FM_SSH_EXTRA_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  ARGUMENTS="$args" bash "$block"
}
