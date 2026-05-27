#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
# Config lives under .github/linters/ (the conventional super-linter path) rather
# than the repo-root .markdownlint.json.
npx --yes markdownlint-cli "plugin/**/*.md" "*.md" -c .github/linters/markdownlint.json
