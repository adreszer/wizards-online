#!/usr/bin/env bash
# Runs the game (or a scene) from a fresh checkout. Performs the one-time
# Godot import first if the project has never been opened.
# Usage: tools/run.sh                       # play
#        tools/run.sh -- --name=Rowan --instance=2   # second client
#        tools/run.sh tests/run_tests.tscn  # headless-friendly scene
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
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "First run: importing project resources..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --path . "$@"
