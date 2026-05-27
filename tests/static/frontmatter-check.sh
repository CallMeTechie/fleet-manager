#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
rc=0
for md in plugin/commands/*.md; do
  head -10 "$md" | grep -qE '^description:' || { echo "MISSING description: $md"; rc=1; }
  head -10 "$md" | grep -qE '^allowed-tools:' || { echo "MISSING allowed-tools: $md"; rc=1; }
done
for md in plugin/agents/*.md; do
  head -10 "$md" | grep -qE '^name:' || { echo "MISSING name: $md"; rc=1; }
  head -10 "$md" | grep -qE '^description:' || { echo "MISSING description: $md"; rc=1; }
done
[ "$rc" -eq 0 ] && echo "frontmatter OK"
exit $rc
