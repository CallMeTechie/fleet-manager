---
description: Connectivity and health check for a server — SSH reachability, passwordless sudo, docker presence, disk usage, and load.
allowed-tools: Bash, Read, Write, Edit
---

# Diag

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"

NAME="$(resolve_server "$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')")"
build_ssh "$NAME"
echo_target "$NAME"
echo "── Diagnostics ──"

# 1. SSH reachability
if "${FM_SSH[@]}" "echo OK" 2>/dev/null | grep -qx OK; then
  echo "PASS  SSH reachable"
else
  echo "FAIL  SSH unreachable — run /setup-ssh $NAME (key not deployed?), check port/host."
  exit 1
fi

# 2. Passwordless sudo
if "${FM_SSH[@]}" "sudo -n true 2>/dev/null"; then
  echo "PASS  passwordless sudo available"
else
  echo "WARN  no passwordless sudo (privileged ops need a NOPASSWD sudoers drop-in)"
fi

# 3. Docker presence + working invocation (probe order: no-sudo, sudo, abs paths)
DOCKER_CMD=""
for cand in "docker" "sudo -n docker" "sudo -n /usr/local/bin/docker" "/usr/local/bin/docker"; do
  if "${FM_SSH[@]}" "$cand info --format '{{.ServerVersion}}' 2>/dev/null" | grep -q '^[0-9][0-9]*\.[0-9]'; then
    DOCKER_CMD="$cand"; break
  fi
done
if [ -n "$DOCKER_CMD" ]; then
  echo "PASS  docker present (via: $DOCKER_CMD)"
else
  echo "WARN  docker not found (Phase 2 compose features unavailable)"
fi

# 4. Disk usage (root fs) — capture first so a transient SSH error here does NOT
#    abort the whole command under `set -e`/`pipefail` after step 1 passed (C1).
if disk_out="$("${FM_SSH[@]}" "df -h / | tail -1" 2>/dev/null)"; then
  printf '%s\n' "$disk_out" | awk '{print "INFO  disk / used "$5" ("$3"/"$2")"}'
else
  echo "WARN  disk query failed (transient SSH error?)"
fi

# 5. Load
if up_out="$("${FM_SSH[@]}" "uptime" 2>/dev/null)"; then
  printf '%s\n' "$up_out" | sed 's/^/INFO  /'
else
  echo "WARN  uptime query failed"
fi
```

After printing, update the **Discovered State** section and the UTC **Last Updated**
line of `context/servers/<name>.md` (use the lib's `sanitize_value` on stored values).
Also persist the docker probe: set `docker_available` to `yes`/`no` and `docker_cmd`
to `$DOCKER_CMD` (or `_not configured_`). **Lazy migration** for pre-Phase-2 profiles
that lack the `docker_cmd` line — insert it after `- docker_available:`:

```bash
if ! grep -q '^- docker_cmd:' "$PROFILE"; then
  TMP_P="$(mktemp)"
  awk '/^- docker_available:/ { print; print "- docker_cmd: _not configured_"; next } { print }' "$PROFILE" > "$TMP_P" && mv "$TMP_P" "$PROFILE"
fi
```
