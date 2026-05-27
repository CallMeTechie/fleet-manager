---
description: Mirror a directory local↔server via rsync. Dry-run by default; --apply to execute. --delete needs --confirm-delete=<server>.
argument-hint: "<src> <dst> [--apply] [--delete --confirm-delete=<server>] [--confirm=<server>]"
allowed-tools: Bash, Read
---

# Sync

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_transfer-lib.sh"

SRC=""; DST=""; APPLY=0; DELETE=0; TOKEN=""; DELTOKEN=""
set -f
# shellcheck disable=SC2086  # intentional: split ARGUMENTS into positional params
set -- ${ARGUMENTS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --delete) DELETE=1 ;;
    --confirm=*) TOKEN="${1#*=}" ;;
    --confirm-delete=*) DELTOKEN="${1#*=}" ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) if [ -z "$SRC" ]; then SRC="$1"; elif [ -z "$DST" ]; then DST="$1"; else echo "Too many args" >&2; exit 1; fi ;;
  esac
  shift
done
if [ -z "$SRC" ] || [ -z "$DST" ]; then echo "Usage: /sync <src> <dst> [--apply] [--delete --confirm-delete=<server>]" >&2; exit 1; fi

parse_endpoint "$SRC"; SRC_KIND="$FM_EP_KIND"; SRC_SERVER="$FM_EP_SERVER"; SRC_PATH="$FM_EP_PATH"
parse_endpoint "$DST"; DST_KIND="$FM_EP_KIND"; DST_SERVER="$FM_EP_SERVER"; DST_PATH="$FM_EP_PATH"
if [ "$SRC_KIND" = remote ] && [ "$DST_KIND" = remote ]; then echo "ERROR: server↔server not supported." >&2; exit 1; fi
if [ "$SRC_KIND" = local ] && [ "$DST_KIND" = local ]; then echo "ERROR: both paths local — use rsync locally." >&2; exit 1; fi
if [ "$DST_KIND" = remote ]; then SERVER="$DST_SERVER"; else SERVER="$SRC_SERVER"; fi
load_profile "$SERVER"; echo_target "$SERVER"   # project convention: show target first

is_scope_authorized "$SERVER" file_transfer || { echo "REFUSED: scope 'file_transfer' not authorized for '$SERVER'." >&2; exit 1; }
if ! local_has_rsync; then echo "ERROR: rsync not found locally — /sync requires rsync (install it)." >&2; exit 1; fi
if ! remote_has_rsync "$SERVER"; then echo "ERROR: rsync not found on '$SERVER' — /sync requires rsync on both ends." >&2; exit 1; fi

if [ "$DST_KIND" = remote ] && is_protected_path "$SERVER" "$DST_PATH"; then
  confirm_destructive "$SERVER" "$TOKEN" || exit 1
fi

build_rsync_rsh "$SERVER"
if [ "$SRC_KIND" = remote ]; then RS_SRC="$FM_REMOTE:$SRC_PATH"; else RS_SRC="$SRC_PATH"; fi
if [ "$DST_KIND" = remote ]; then RS_DST="$FM_REMOTE:$DST_PATH"; else RS_DST="$DST_PATH"; fi

OPTS=(-a -i -s)
[ "$DELETE" -eq 1 ] && OPTS+=(--delete)
if [ "$APPLY" -eq 0 ]; then
  OPTS+=(--dry-run)
  echo "── DRY RUN (no changes) — re-run with --apply to execute ──"
  rsync "${OPTS[@]}" -e "$FM_RSYNC_RSH" "$RS_SRC" "$RS_DST"
  echo "(Tip: check trailing slashes — 'dir' copies the dir, 'dir/' copies its contents.)"
  exit 0
fi

# --apply path: gate --delete behind the match token.
if [ "$DELETE" -eq 1 ] && [ "$DELTOKEN" != "$SERVER" ]; then
  echo "REFUSED: --delete needs --confirm-delete=$SERVER (you typed: '${DELTOKEN:-<none>}')." >&2
  echo "Inspect first with a dry run: /sync $SRC $DST --delete   (no --apply)" >&2
  exit 1
fi
if rsync "${OPTS[@]}" -e "$FM_RSYNC_RSH" "$RS_SRC" "$RS_DST"; then
  if [ "$DELETE" -eq 1 ]; then echo "Verdict: synced (with --delete)."; else echo "Verdict: synced."; fi
else
  echo "ERROR: rsync failed." >&2; exit 1
fi
```
