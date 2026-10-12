#!/usr/bin/env bash
# Offline verification in one command: regenerates the castle and the server's
# generated content, fails if either differs from what is committed, then runs
# the script check and the gameplay tests. Logs go to .godot/check/ (Godot
# buffers piped output, so it is never piped).
# Usage: tools/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if [ -z "$GODOT" ]; then
  echo "Godot 4.7 not found. Set GODOT=/path/to/godot or install it." >&2
  exit 1
fi
LOGS=.godot/check
mkdir -p "$LOGS"

step() { printf '\n== %s\n' "$1"; }
fail() { echo "FAILED: $1 (log: $2)" >&2; exit 1; }

step "import"
"$GODOT" --headless --path . --import >"$LOGS/import.log" 2>&1 || true

step "generate castle"
python3 tools/generate_castle.py >"$LOGS/castle.log" 2>&1 || fail "castle generator" "$LOGS/castle.log"

step "export server content"
"$GODOT" --headless --path . tools/export_server_content.tscn >"$LOGS/export.log" 2>&1 || fail "exporter" "$LOGS/export.log"

step "generated files committed"
if ! git diff --quiet -- levels/castle nakama/modules || [ -n "$(git ls-files --others --exclude-standard -- nakama/modules levels/castle)" ]; then
  git status --short -- levels/castle nakama/modules
  echo "Generated files differ from the commit; review and commit them." >&2
  exit 1
fi

step "scripts"
"$GODOT" --headless --path . tests/check_scripts.tscn >"$LOGS/check_scripts.log" 2>&1 || fail "check_scripts" "$LOGS/check_scripts.log"

step "gameplay tests"
"$GODOT" --headless --path . tests/run_tests.tscn >"$LOGS/run_tests.log" 2>&1 || { grep -E "FAIL|passed" "$LOGS/run_tests.log" | tail -20; fail "run_tests" "$LOGS/run_tests.log"; }
grep -E "passed" "$LOGS/run_tests.log" | tail -1
echo "all checks passed"
