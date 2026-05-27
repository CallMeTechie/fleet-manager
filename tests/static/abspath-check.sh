#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
rc=0
# Flag a bare `sudo -n docker` (must be /usr/local/bin/docker etc.) inside commands.
if grep -rnE 'sudo -n[[:space:]]+docker([[:space:]]|$)' plugin/commands/*.md; then
  echo "ABSPATH: use an absolute path for docker under sudo over SSH"; rc=1
fi
[ "$rc" -eq 0 ] && echo "abspath OK"
exit $rc
