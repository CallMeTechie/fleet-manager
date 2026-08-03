#!/usr/bin/env bash
# Unit tests for context-dir resolution and the pre-0.3.3 migration.
# These cannot live in test-fleet-lib.sh: that file exports FM_CONTEXT_DIR
# globally, which is exactly the branch we need to NOT take here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$ROOT/plugin/commands/_fleet-lib.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want='$2' got='$1')"; fi; }
# Spelled out rather than `A && B || C`: with that idiom C also runs when A is
# true but B fails, which turns a single result into a pass *and* a fail (SC2015).
assert_exists() { if [ -e "$1" ]; then ok "$2"; else no "$2"; fi; }
assert_absent() { if [ -e "$1" ]; then no "$2"; else ok "$2"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Stage a fake plugin tree so the lib can be sourced from a version-pinned path
# like the real plugin cache: <root>/0.3.2/commands/_fleet-lib.sh
FAKE="$TMP/cache/fleet-manager/0.3.2"
mkdir -p "$FAKE/commands" "$FAKE/context/servers"
cp "$LIB" "$FAKE/commands/_fleet-lib.sh"

# --- 1. explicit override wins ---
got="$(FM_CONTEXT_DIR="$TMP/explicit" bash -c 'source "$1"; printf "%s" "$FM_CONTEXT"' _ "$FAKE/commands/_fleet-lib.sh")"
assert_eq "$got" "$TMP/explicit" "FM_CONTEXT_DIR override wins"

# --- 2. default follows XDG_CONFIG_HOME, NOT the lib location ---
got="$(XDG_CONFIG_HOME="$TMP/xdg" bash -c 'unset FM_CONTEXT_DIR; source "$1"; printf "%s" "$FM_CONTEXT"' _ "$FAKE/commands/_fleet-lib.sh")"
assert_eq "$got" "$TMP/xdg/fleet-manager" "default honours XDG_CONFIG_HOME"

# --- 3. default falls back to ~/.config when XDG is unset ---
got="$(HOME="$TMP/home" bash -c 'unset FM_CONTEXT_DIR XDG_CONFIG_HOME; source "$1"; printf "%s" "$FM_CONTEXT"' _ "$FAKE/commands/_fleet-lib.sh")"
assert_eq "$got" "$TMP/home/.config/fleet-manager" "default falls back to \$HOME/.config"

# --- 4. the version-pinned plugin dir is never the default (the 0.3.3 bug) ---
case "$got" in
  *"/cache/fleet-manager/0.3.2/"*) no "default must not resolve into the plugin dir" ;;
  *) ok "default never resolves into the version-pinned plugin dir" ;;
esac

# --- 5. migration copies a stranded inventory forward ---
printf '# Server: web\n' > "$FAKE/context/servers/web.md"
printf '# Server: db\n'  > "$FAKE/context/servers/db.md"
printf 'web\n'           > "$FAKE/context/active-server"
# templates must not count as profiles
printf 'template\n'      > "$FAKE/context/servers/EXAMPLE.md.template"

XDG_CONFIG_HOME="$TMP/mig" bash -c 'unset FM_CONTEXT_DIR; source "$1"' _ "$FAKE/commands/_fleet-lib.sh" 2>/dev/null
assert_exists "$TMP/mig/fleet-manager/servers/web.md" "migration copied web.md"
assert_exists "$TMP/mig/fleet-manager/servers/db.md"  "migration copied db.md"
assert_eq "$(cat "$TMP/mig/fleet-manager/active-server" 2>/dev/null)" "web" "migration carried active-server"
assert_absent "$TMP/mig/fleet-manager/servers/EXAMPLE.md.template" "template not migrated"
assert_exists "$FAKE/context/servers/web.md" "migration is non-destructive (original kept)"

# --- 6. migration never clobbers a populated inventory ---
mkdir -p "$TMP/live/fleet-manager/servers"
printf '# Server: live\n' > "$TMP/live/fleet-manager/servers/live.md"
XDG_CONFIG_HOME="$TMP/live" bash -c 'unset FM_CONTEXT_DIR; source "$1"' _ "$FAKE/commands/_fleet-lib.sh" 2>/dev/null
assert_absent "$TMP/live/fleet-manager/servers/web.md" "populated inventory left untouched"

# --- 7. migration is a no-op when the override is set ---
XDG_CONFIG_HOME="$TMP/unused" FM_CONTEXT_DIR="$TMP/override" bash -c 'source "$1"' _ "$FAKE/commands/_fleet-lib.sh" 2>/dev/null
assert_absent "$TMP/override/servers" "no migration under FM_CONTEXT_DIR"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
