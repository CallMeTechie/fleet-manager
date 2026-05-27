#!/usr/bin/env bash
# Docker / Compose helpers for fleet-manager. Sourced by /compose-* and /docker-list.
# shellcheck shell=bash
# Sources _fleet-lib.sh for server resolution + gates.

_cl_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_cl_dir/_fleet-lib.sh"

FM_DOCKER_ALLOW='^(sudo -n )?(/[A-Za-z0-9/_.-]+/)?docker$'
FM_COMPOSE_PATH_RE='^/[A-Za-z0-9/_.-]+\.ya?ml$'

# resolve_docker_cmd <server> — sets FM_DOCKER from the profile's docker_cmd.
resolve_docker_cmd() {
  local name="$1" profile avail cmd
  profile="$FM_SERVERS_DIR/$name.md"
  avail="$(text_field "$profile" docker_available)"
  if [ "$avail" = "no" ]; then
    echo "ERROR: docker not available on '$name' (run /diag $name to re-probe)." >&2; return 1
  fi
  cmd="$(text_field "$profile" docker_cmd)"
  if [ -z "$cmd" ]; then
    echo "ERROR: docker_cmd not configured for '$name' (run /diag $name)." >&2; return 1
  fi
  if ! [[ "$cmd" =~ $FM_DOCKER_ALLOW ]]; then
    echo "ERROR: docker_cmd '$cmd' for '$name' fails the allowlist — refusing to use it." >&2; return 1
  fi
  # shellcheck disable=SC2034  # consumed by callers + docker_precheck
  FM_DOCKER="$cmd"
}

# docker_precheck — verify the daemon is reachable via FM_DOCKER over FM_SSH.
docker_precheck() {
  local out
  out="$("${FM_SSH[@]}" "$FM_DOCKER info --format '{{.ServerVersion}}' 2>&1" || true)"
  # Tolerant version match (version may be preceded by a sudo lecture line/token).
  if echo "$out" | grep -qE '(^|[[:space:]])[0-9]+\.[0-9]'; then return 0; fi
  if [ -z "$out" ]; then
    echo "ERROR: no response from the host (SSH transport failure or empty docker output)." >&2; return 1
  fi
  if echo "$out" | grep -qi "a password is required"; then
    echo "ERROR: '$FM_DOCKER' needs a password — passwordless sudo for docker not configured." >&2
  elif echo "$out" | grep -qi "Cannot connect to the Docker daemon"; then
    echo "ERROR: Docker daemon not running on this host." >&2
  elif echo "$out" | grep -qi "not found"; then
    echo "ERROR: docker not found via '$FM_DOCKER' — re-run /diag to re-probe." >&2
  else
    echo "ERROR: docker info unexpected output:" >&2; echo "$out" | head -3 >&2
  fi
  return 1
}

# compose_ls_json — raw JSON array of compose projects. Distinguishes a REAL
# failure (SSH/daemon/compose-plugin) from a genuinely empty list (review C2).
compose_ls_json() {
  local out rc
  out="$("${FM_SSH[@]}" "$FM_DOCKER compose ls --all --format json" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: 'docker compose ls' failed on the host (daemon down or compose plugin missing?)." >&2
    return 1
  fi
  if [ -n "$out" ]; then printf '%s' "$out"; else echo "[]"; fi
}

# compose_find_project <name> — echo {Status, ConfigFiles} JSON for exact match, or empty.
# Does NOT swallow jq parse errors as "not found" (review H1): validates array shape first.
compose_find_project() {
  local proj="$1" raw
  raw="$(compose_ls_json)" || return 1
  if ! echo "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: 'docker compose ls' did not return a JSON array — refusing to parse." >&2
    return 1
  fi
  echo "$raw" | jq -c --arg p "$proj" '.[] | select(.Name == $p) | {Status, ConfigFiles}'
}

# compose_config_args <config_files> — emit `-f <path>` per file; validate; error if empty.
compose_config_args() {
  local raw files f out=""
  raw="$(sanitize_value "$1")"
  if [ -z "$raw" ] || [ "$raw" = "null" ]; then
    echo "ERROR: no compose config file for this project — aborting (cannot run compose without -f)." >&2
    return 1
  fi
  IFS=',' read -ra files <<< "$raw"
  for f in "${files[@]}"; do
    f="$(sanitize_value "$f")"
    [ -z "$f" ] && continue
    if ! [[ "$f" =~ $FM_COMPOSE_PATH_RE ]]; then
      echo "ERROR: compose config path '$f' fails validation — refusing to use it." >&2; return 1
    fi
    out="$out -f $f"
  done
  [ -z "$out" ] && { echo "ERROR: no valid compose config file — aborting." >&2; return 1; }
  printf '%s' "${out# }"
}
