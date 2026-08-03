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
  # Subagents are not granted AskUserQuestion — the interaction channel belongs to
  # the main thread. Declaring it produces an agent that aborts at its first
  # question instead of one that asks. Gather the answers in the command and pass
  # them in.
  if head -10 "$md" | grep -qE '^tools:.*AskUserQuestion'; then
    echo "FORBIDDEN AskUserQuestion in agent frontmatter: $md"; rc=1
  fi
done
[ "$rc" -eq 0 ] && echo "frontmatter OK"
exit $rc
