#!/usr/bin/env bash
# Runs the game (or a scene). Imports first whenever a file changed since the
# last import (a fresh checkout, a pull with new sounds, models or class_names);
# without it new assets have no loader and scripts using new classes fail.
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
STAMP=.godot/run_import.stamp
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f "$STAMP" ] \
  || [ -n "$(find . \( -path ./.godot -o -path ./.git \) -prune -o -type f -newer "$STAMP" -print -quit)" ]; then
  echo "Files changed since the last import: importing project resources..."
  touch "$STAMP.next"
  if "$GODOT" --headless --path . --import >/dev/null 2>&1; then
    mv "$STAMP.next" "$STAMP"
  else
    rm -f "$STAMP.next"
    echo "Import reported errors (run: $GODOT --headless --path . --import)" >&2
  fi
fi
exec "$GODOT" --path . "$@"
