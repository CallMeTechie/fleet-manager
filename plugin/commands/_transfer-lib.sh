#!/usr/bin/env bash
# File-transfer helpers for fleet-manager. Sourced by /copy and /sync.
# shellcheck shell=bash
_tl_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_tl_dir/_fleet-lib.sh"

# parse_endpoint <arg> — sets FM_EP_KIND (remote|local), FM_EP_SERVER, FM_EP_PATH.
# Remote iff the part before the first ':' is an existing inventory server.
parse_endpoint() {
  local arg="$1" before="${1%%:*}"
  # shellcheck disable=SC2034  # FM_EP_* are consumed by /copy and /sync, not within the lib
  if [ "$before" != "$arg" ] && profile_exists "$before" 2>/dev/null; then
    FM_EP_KIND="remote"; FM_EP_SERVER="$before"; FM_EP_PATH="${arg#*:}"
  else
    FM_EP_KIND="local"; FM_EP_SERVER=""; FM_EP_PATH="$arg"
  fi
}

# is_protected_path <server> <path> — exit 0 if path equals or is under a protected_paths entry.
is_protected_path() {
  local name="$1" path="$2" profile list e
  profile="$FM_SERVERS_DIR/$name.md"
  list="$(text_field "$profile" protected_paths)"
  [ -z "$list" ] && return 1
  local -a entries
  IFS=',' read -ra entries <<< "$list"
  for e in "${entries[@]}"; do
    e="$(sanitize_value "$e")"; [ -z "$e" ] && continue
    case "$path" in "$e"|"$e"/*) return 0;; esac
  done
  return 1
}

# build_rsync_rsh <server> — sets FM_RSYNC_RSH (ssh command string) + FM_REMOTE (user@host).
build_rsync_rsh() {
  load_profile "$1" || return 1
  local extra="${FM_SSH_EXTRA_OPTS:-}"
  # shellcheck disable=SC2034,SC2153  # FM_RSYNC_RSH consumed by callers; FM_KEY_PATH set by load_profile (sourced lib)
  FM_RSYNC_RSH="ssh -i $FM_KEY_PATH -o BatchMode=yes -o ConnectTimeout=$FM_TIMEOUT -p $FM_PORT${extra:+ $extra}"
  # shellcheck disable=SC2034
  FM_REMOTE="$FM_USER@$FM_HOST"
}

# local_has_rsync / remote_has_rsync — rsync presence on each end.
local_has_rsync() { command -v rsync >/dev/null 2>&1; }
remote_has_rsync() { build_ssh "$1" || return 1; "${FM_SSH[@]}" "command -v rsync >/dev/null 2>&1"; }
