---
description: Copy files between local and a server (rsync, scp fallback). Syntax — local↔ <server>:<path>. Scope-gated (file_transfer).
argument-hint: "<src> <dst> [--confirm=<server>]"
allowed-tools: Bash, Read
---

# Copy

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_transfer-lib.sh"

SRC=""; DST=""; TOKEN=""
set -f
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm=*) TOKEN="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SRC" ]; then SRC="$1"; elif [ -z "$DST" ]; then DST="$1"; else echo "Too many args" >&2; exit 1; fi ;;
  esac
  shift
done
if [ -z "$SRC" ] || [ -z "$DST" ]; then echo "Usage: /copy <src> <dst>  (one side is <server>:<path>)" >&2; exit 1; fi

parse_endpoint "$SRC"; SRC_KIND="$FM_EP_KIND"; SRC_SERVER="$FM_EP_SERVER"; SRC_PATH="$FM_EP_PATH"
parse_endpoint "$DST"; DST_KIND="$FM_EP_KIND"; DST_SERVER="$FM_EP_SERVER"; DST_PATH="$FM_EP_PATH"

if [ "$SRC_KIND" = remote ] && [ "$DST_KIND" = remote ]; then echo "ERROR: server↔server not supported in this phase." >&2; exit 1; fi
if [ "$SRC_KIND" = local ] && [ "$DST_KIND" = local ]; then echo "ERROR: both paths are local — use cp." >&2; exit 1; fi

if [ "$DST_KIND" = remote ]; then SERVER="$DST_SERVER"; else SERVER="$SRC_SERVER"; fi
load_profile "$SERVER"; echo_target "$SERVER"   # project convention: show target first
is_scope_authorized "$SERVER" file_transfer || { echo "REFUSED: scope 'file_transfer' not authorized for '$SERVER'." >&2; exit 1; }

# Protected-path gate: only when writing INTO a remote destination.
if [ "$DST_KIND" = remote ] && is_protected_path "$SERVER" "$DST_PATH"; then
  confirm_destructive "$SERVER" "$TOKEN" || exit 1
fi

build_rsync_rsh "$SERVER"
if [ "$SRC_KIND" = remote ]; then RS_SRC="$FM_REMOTE:$SRC_PATH"; else RS_SRC="$SRC_PATH"; fi
if [ "$DST_KIND" = remote ]; then RS_DST="$FM_REMOTE:$DST_PATH"; else RS_DST="$DST_PATH"; fi

if local_has_rsync && remote_has_rsync "$SERVER"; then
  rsync -a -s -e "$FM_RSYNC_RSH" "$RS_SRC" "$RS_DST" && echo "Verdict: copied (rsync)."
else
  # scp fallback — refuse paths with spaces/metacharacters (no --protect-args equivalent).
  remote_path="$DST_PATH"; [ "$SRC_KIND" = remote ] && remote_path="$SRC_PATH"
  case "$remote_path" in *[!A-Za-z0-9/._-]*) echo "ERROR: rsync unavailable and remote path has special chars — install rsync." >&2; exit 1;; esac
  # scp must honor the same extra ssh opts (ProxyJump / host-key bypass for tests).
  scp_extra=()
  [ -n "${FM_SSH_EXTRA_OPTS:-}" ] && read -ra scp_extra <<< "$FM_SSH_EXTRA_OPTS"
  if [ "$SRC_KIND" = remote ]; then
    scp -i "$FM_KEY_PATH" -o BatchMode=yes ${scp_extra[@]+"${scp_extra[@]}"} -P "$FM_PORT" -r "$FM_REMOTE:$SRC_PATH" "$DST_PATH" && echo "Verdict: copied (scp)."
  else
    scp -i "$FM_KEY_PATH" -o BatchMode=yes ${scp_extra[@]+"${scp_extra[@]}"} -P "$FM_PORT" -r "$SRC_PATH" "$FM_REMOTE:$DST_PATH" && echo "Verdict: copied (scp)."
  fi
fi
```

**Protected destination (prose):** if the destination is under a protected path, the gate requires `--confirm=<server>` (matching the server name) — confirm the user's intent before re-running with the token. `confirm_destructive` refuses without it.
