#!/usr/bin/env bash
# Shared helpers for fleet-manager commands. Sourced from each command-markdown.
# shellcheck shell=bash
# Run shellcheck directly: shellcheck plugin/commands/_fleet-lib.sh
#
# This file is SOURCED, so it must not call `set -e` or `exit`. Functions
# `return` non-zero on error and print diagnostics to stderr.

# Context dir, in precedence order:
#   1. $FM_CONTEXT_DIR — explicit override (tests, custom setups)
#   2. XDG config dir  — the default
#
# It must NOT be derived from this lib's own location. Claude Code installs the
# plugin into a version-pinned cache directory (.../fleet-manager/0.3.2/), so a
# lib-relative context dir is abandoned on every plugin update: the new version
# starts with an empty inventory and the old profiles are stranded in the
# previous version's directory. Never resolve it from the CWD either — commands
# source us via an absolute $CLAUDE_PLUGIN_ROOT and run from anywhere
# (review #3, Critical).
if [ -n "${FM_CONTEXT_DIR:-}" ]; then
  FM_CONTEXT="$FM_CONTEXT_DIR"
else
  FM_CONTEXT="${XDG_CONFIG_HOME:-$HOME/.config}/fleet-manager"
fi
FM_SERVERS_DIR="$FM_CONTEXT/servers"
FM_ACTIVE_FILE="$FM_CONTEXT/active-server"

# _fm_count_profiles <dir> — number of real profiles in <dir>. Templates are
# named *.md.template and so never match the *.md glob.
_fm_count_profiles() {
  local f n=0
  for f in "${1:-}"/*.md; do [ -e "$f" ] && n=$((n+1)); done
  printf '%s' "$n"
}

# Migrate a pre-0.3.3 in-plugin inventory forward, once. Only fires when the
# legacy directory holds real profiles and the new one holds none, so it cannot
# clobber a live inventory. Copies rather than moves — the originals stay put in
# the old version's cache directory, which the next plugin update discards.
_fm_migrate_legacy_context() {
  local lib_dir legacy
  [ -n "${FM_CONTEXT_DIR:-}" ] && return 0
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 0
  legacy="$(cd "$lib_dir/.." && pwd)/context" || return 0
  [ "$legacy" = "$FM_CONTEXT" ] && return 0
  [ -d "$legacy/servers" ] || return 0
  [ "$(_fm_count_profiles "$legacy/servers")" -gt 0 ] || return 0
  [ "$(_fm_count_profiles "$FM_SERVERS_DIR")" -eq 0 ] || return 0

  mkdir -p "$FM_SERVERS_DIR" || return 0
  cp -p "$legacy"/servers/*.md "$FM_SERVERS_DIR"/ 2>/dev/null || return 0
  if [ -f "$legacy/active-server" ]; then
    cp -p "$legacy/active-server" "$FM_ACTIVE_FILE" 2>/dev/null || true
  fi
  echo "fleet-manager: migrated inventory $legacy -> $FM_CONTEXT (originals left in place)." >&2
}
_fm_migrate_legacy_context

# sanitize_value <raw> — strip CR and surrounding whitespace from any value
# that will be written into a profile (Concern 4, R2).
sanitize_value() {
  printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# validate_server_name <name> — filename-safe, no path traversal.
validate_server_name() {
  local name="${1:-}"
  if [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    return 0
  fi
  echo "ERROR: invalid server name '$name' (allowed: A-Z a-z 0-9 _ -)" >&2
  return 1
}

# strict_field <profile> <key> — exactly one token, placeholder/empty/multiword = error.
# For host/port/user/key_path/connect_timeout_seconds only.
strict_field() {
  local profile="$1" key="$2" line rest
  line="$(grep -m1 -E "^- ${key}:" "$profile" 2>/dev/null || true)"
  if [ -z "$line" ]; then
    echo "ERROR: field '$key' not found in $profile" >&2
    return 1
  fi
  # Use ${line#*:} (no trailing space) — sanitize_value trims leading space.
  # Consistent with text_field and tolerant of "key:value" without a space (H1).
  rest="$(sanitize_value "${line#*:}")"
  if [ -z "$rest" ] || [ "$rest" = "_not configured_" ]; then
    echo "ERROR: field '$key' is not configured in $profile" >&2
    return 1
  fi
  if printf '%s' "$rest" | grep -q '[[:space:]]'; then
    echo "ERROR: field '$key' in $profile must be a single token (got: '$rest')" >&2
    return 1
  fi
  printf '%s' "$rest"
}

# text_field <profile> <key> — full free-text value after the colon, trimmed.
# Placeholder -> empty. Display only; NEVER used as an SSH argument.
text_field() {
  local profile="$1" key="$2" line rest
  line="$(grep -m1 -E "^- ${key}:" "$profile" 2>/dev/null || true)"
  [ -n "$line" ] || { printf ''; return 0; }
  rest="$(sanitize_value "${line#*:}")"
  [ "$rest" = "_not configured_" ] && rest=""
  printf '%s' "$rest"
}

# load_profile <name> — sets FM_HOST/FM_PORT/FM_USER/FM_KEY_PATH/FM_TIMEOUT.
# Validates with regexes; expands a leading ~ in key_path (Concern 1).
load_profile() {
  # Split the declaration: referencing $name in the same `local` as `profile`
  # is unreliable and ShellCheck-flagged (SC2318) (review #4, C1).
  local name="$1" profile
  profile="$FM_SERVERS_DIR/$name.md"
  if [ ! -f "$profile" ]; then
    echo "ERROR: profile not found: $profile" >&2
    return 1
  fi
  FM_HOST="$(strict_field "$profile" host)" || return 1
  FM_PORT="$(strict_field "$profile" port)" || return 1
  FM_USER="$(strict_field "$profile" user)" || return 1
  FM_KEY_PATH="$(strict_field "$profile" key_path)" || return 1
  # Timeout is optional: single source of truth — read silently, default+validate below (H2).
  FM_TIMEOUT="$(strict_field "$profile" connect_timeout_seconds 2>/dev/null)" || FM_TIMEOUT=10

  # Tilde expansion: a quoted ~ is NOT expanded by the shell.
  FM_KEY_PATH="${FM_KEY_PATH/#\~/$HOME}"

  if ! [[ "$FM_HOST" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "ERROR: invalid host '$FM_HOST' in $profile" >&2; return 1
  fi
  if ! [[ "$FM_PORT" =~ ^[0-9]{1,5}$ ]] || [ "$FM_PORT" -lt 1 ] || [ "$FM_PORT" -gt 65535 ]; then
    echo "ERROR: invalid port '$FM_PORT' in $profile" >&2; return 1
  fi
  if ! [[ "$FM_USER" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "ERROR: invalid user '$FM_USER' in $profile" >&2; return 1
  fi
  [[ "$FM_TIMEOUT" =~ ^[0-9]+$ ]] || FM_TIMEOUT=10
}

# build_ssh <name> — sets the FM_SSH argument array (never a string).
build_ssh() {
  load_profile "$1" || return 1
  local -a extra=()
  # FM_SSH_EXTRA_OPTS: optional extra ssh flags (e.g. ProxyJump; tests use it for
  # StrictHostKeyChecking=no). Word-split intentionally; values are operator-controlled.
  if [ -n "${FM_SSH_EXTRA_OPTS:-}" ]; then read -ra extra <<< "$FM_SSH_EXTRA_OPTS"; fi
  # shellcheck disable=SC2034  # FM_SSH is consumed by command callers, not within the lib
  FM_SSH=(ssh -i "$FM_KEY_PATH" -o BatchMode=yes -o ConnectTimeout="$FM_TIMEOUT" -p "$FM_PORT" ${extra[@]+"${extra[@]}"} "$FM_USER@$FM_HOST")
}

# echo_target <name> — prints the resolved target before execution (Concern 3).
# Requires load_profile/build_ssh to have run. Defensive defaults so it never
# crashes under `set -u` if a caller reaches here with a broken profile (C2).
echo_target() {
  echo "→ Ziel: ${1:-?} (${FM_USER:-?}@${FM_HOST:-?}:${FM_PORT:-?})"
}

# profile_exists <name> — 0 if a server profile exists, 1 otherwise. Testable
# basis for /add-server's re-add protection (H3).
profile_exists() {
  local name="$1"
  validate_server_name "$name" || return 1
  [ -f "$FM_SERVERS_DIR/$name.md" ]
}

# list_server_names — one name per line (basename without .md). Templates end in
# .md.template and are excluded by the *.md glob automatically.
list_server_names() {
  local f base
  [ -d "$FM_SERVERS_DIR" ] || return 0
  for f in "$FM_SERVERS_DIR"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .md)"
    printf '%s\n' "$base"
  done
}

# resolve_server [<arg>] — prints the server to act on. Arg wins; else active.
resolve_server() {
  local arg="${1:-}" name=""
  if [ -n "$arg" ]; then
    name="$arg"
  elif [ -f "$FM_ACTIVE_FILE" ]; then
    name="$(tr -d '[:space:]' < "$FM_ACTIVE_FILE")"
  fi
  if [ -z "$name" ]; then
    {
      echo "ERROR: no server given and no active server set. Run /use <name> or pass a server."
      echo "Available servers:"; list_server_names
    } >&2
    return 1
  fi
  # Validate the name before using it as a path component — guards against a
  # manually corrupted active-server file (e.g. "../etc"); no path traversal (M4).
  if ! validate_server_name "$name"; then
    return 1
  fi
  if [ ! -f "$FM_SERVERS_DIR/$name.md" ]; then
    {
      echo "ERROR: server '$name' not found in inventory."
      echo "Available servers:"; list_server_names
    } >&2
    return 1
  fi
  printf '%s' "$name"
}

# set_active <name> — atomically point active-server at <name>.
set_active() {
  local name="$1" tmp
  validate_server_name "$name" || return 1
  if [ ! -f "$FM_SERVERS_DIR/$name.md" ]; then
    echo "ERROR: server '$name' not found" >&2; return 1
  fi
  mkdir -p "$FM_CONTEXT"
  tmp="$(mktemp "$FM_CONTEXT/.active-server.XXXXXX")"
  printf '%s\n' "$name" > "$tmp"
  mv "$tmp" "$FM_ACTIVE_FILE"
}

# write_inventory — regenerate inventory.md atomically from all profiles.
write_inventory() {
  local tmp active name host desc mark
  mkdir -p "$FM_CONTEXT"
  active=""
  [ -f "$FM_ACTIVE_FILE" ] && active="$(tr -d '[:space:]' < "$FM_ACTIVE_FILE")"
  tmp="$(mktemp "$FM_CONTEXT/.inventory.XXXXXX")"
  {
    echo "# fleet-manager — Inventory"
    echo
    echo "_Generated by fleet-manager. Do not edit by hand._"
    echo
    echo "| Active | Server | Host | Description |"
    echo "| - | - | - | - |"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      host="$(text_field "$FM_SERVERS_DIR/$name.md" host)"
      desc="$(text_field "$FM_SERVERS_DIR/$name.md" description)"
      mark=" "; [ "$name" = "$active" ] && mark="*"
      echo "| $mark | $name | $host | $desc |"
    done < <(list_server_names)
  } > "$tmp"
  mv "$tmp" "$FM_CONTEXT/inventory.md"
}

# --- Phase 2 gates ---

# is_scope_authorized <server> <scope> — exit 0 if the scope checkbox is ticked.
is_scope_authorized() {
  local name="$1" scope="$2" profile
  profile="$FM_SERVERS_DIR/$name.md"
  [ -f "$profile" ] || { echo "ERROR: profile not found: $profile" >&2; return 1; }
  grep -qE "^- \[x\] ${scope}\$" "$profile"
}

# is_protected_resource <server> <kind> <value> — exit 0 if value is whitelisted.
# kind: compose_project -> critical_compose_projects ; path -> protected_paths
is_protected_resource() {
  local name="$1" kind="$2" value="$3" profile field list entry
  profile="$FM_SERVERS_DIR/$name.md"
  case "$kind" in
    compose_project) field="critical_compose_projects" ;;
    path)            field="protected_paths" ;;
    *) echo "ERROR: unknown protected-resource kind '$kind'" >&2; return 2 ;;
  esac
  [ -f "$profile" ] || { echo "ERROR: profile not found: $profile" >&2; return 2; }
  list="$(text_field "$profile" "$field")"
  [ -z "$list" ] && return 1
  local -a entries
  IFS=',' read -ra entries <<< "$list"
  for entry in "${entries[@]}"; do
    entry="$(sanitize_value "$entry")"
    [ -n "$entry" ] && [ "$entry" = "$value" ] && return 0
  done
  return 1
}

# confirm_destructive <project> <provided_token> — allow if token matches project
# OR FM_CONFIRM_CRITICAL=yes. Refuses otherwise (fail-safe against accidental runs).
confirm_destructive() {
  local project="$1" token="${2:-}"
  [ "$token" = "$project" ] && return 0
  [ "${FM_CONFIRM_CRITICAL:-no}" = "yes" ] && return 0
  {
    echo "REFUSED: '$project' is a protected (critical) project."
    echo "To proceed, re-run with the confirmation token:  --confirm=$project"
    echo "(or set FM_CONFIRM_CRITICAL=yes for non-interactive use)"
  } >&2
  return 1
}

# --- Phase 3: fleet health row ---

# server_health_line <name> <active-name> — echo one formatted fleet-summary row.
# Return: 0=UP, 1=DOWN, 2=SKIP. One field-safe SSH round-trip.
server_health_line() {
  local name="$1" active="$2" mark="  " docker line nf os disk load mem
  [ "$name" = "$active" ] && mark="* "
  if ! is_scope_authorized "$name" system_monitoring; then
    printf '%s%-13s %-7s %s\n' "$mark" "$name" "SKIP" "(system_monitoring off)"; return 2
  fi
  if ! build_ssh "$name"; then
    printf '%s%-13s %-7s\n' "$mark" "$name" "DOWN"; return 1
  fi
  docker="$(text_field "$FM_SERVERS_DIR/$name.md" docker_available)"; [ -n "$docker" ] || docker="?"
  # Snippet is sent verbatim to the REMOTE shell — single quotes are intentional
  # (it must NOT expand locally). LC_ALL=C stabilizes the `free` label.
  # shellcheck disable=SC2016
  local snippet='LC_ALL=C; . /etc/os-release 2>/dev/null; d=$(df -P / 2>/dev/null | awk "NR==2{print \$5}"); l=$(awk "{print \$1}" /proc/loadavg 2>/dev/null); m=$(LC_ALL=C free 2>/dev/null | awk "/^Mem:/{printf \"%d%%\",(\$3/\$2)*100}"); printf "%s|%s|%s|%s|%s\n" "${PRETTY_NAME:-?}" "${d:-?}" "${l:-?}" "${m:-?}" "$(hostname 2>/dev/null || echo \?)"'
  if ! line="$("${FM_SSH[@]}" "$snippet" 2>/dev/null)"; then
    printf '%s%-13s %-7s\n' "$mark" "$name" "DOWN"; return 1
  fi
  nf="$(awk -F'|' 'END{print NF}' <<<"$line")"
  if [ "$nf" != "5" ]; then
    printf '%s%-13s %-7s\n' "$mark" "$name" "DOWN"; return 1
  fi
  IFS='|' read -r os disk load mem _ <<<"$line"
  printf '%s%-13s %-7s %-15s %-6s %-6s %-6s %s\n' "$mark" "$name" "UP" "$os" "$disk" "$load" "$mem" "$docker"
  return 0
}
