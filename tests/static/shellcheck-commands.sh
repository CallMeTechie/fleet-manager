#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
rc=0

# 1. Standalone shell scripts
while IFS= read -r f; do
  echo "shellcheck: $f"
  shellcheck "$f" || rc=1
done < <(find plugin tests -name '*.sh' -type f)

# 2. Embedded bash fenced blocks in command markdown
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
for md in plugin/commands/*.md; do
  awk '/^```bash$/{f=1;next} /^```$/{f=0} f{print}' "$md" > "$tmpd/block.sh"
  [ -s "$tmpd/block.sh" ] || continue
  echo "shellcheck (embedded): $md"
  # -s bash: blocks start with `set -euo pipefail`, no shebang, so tell shellcheck
  #   the shell explicitly (avoids SC2148) (review #4, C2).
  # commands source the lib and use $ARGUMENTS/$CLAUDE_PLUGIN_ROOT — allow those.
  shellcheck -s bash -x -e SC1091 -e SC2154 "$tmpd/block.sh" || rc=1
done
exit $rc
