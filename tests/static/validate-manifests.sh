#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import json
mp = json.load(open(".claude-plugin/marketplace.json"))
pj = json.load(open("plugin/.claude-plugin/plugin.json"))
assert mp["plugins"][0]["source"] == "./plugin", "marketplace source must be ./plugin"
for k in ("name","version","description","author","license"):
    assert k in pj, f"plugin.json missing {k}"
assert pj["name"] == "fleet-manager", "plugin name mismatch"
print("manifests OK")
PY
