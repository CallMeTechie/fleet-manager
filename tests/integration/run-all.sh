#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0

echo "== test-resolve (no container) =="
bash "$HERE/test-resolve.sh" || rc=1

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  for t in test-diag test-status test-compose-list test-docker-list test-compose-logs test-compose-up test-compose-down test-compose-update test-logs test-command-gates test-health-summary test-copy test-sync; do
    echo "== $t (container) =="
    bash "$HERE/$t.sh" || rc=1
  done
else
  echo "SKIP container tests — docker unavailable"
fi
exit $rc
