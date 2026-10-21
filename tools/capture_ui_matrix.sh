#!/usr/bin/env bash
# Captures the UI gallery (tools/capture_ui.tscn) at every window size, language and
# interface scale the ship check reviews (docs/ui.md, Milestone 72), into
# OUT/<size>_<lang>_<scale>/. Needs a window (not headless); about a minute per run.
#   tools/capture_ui_matrix.sh /absolute/out/dir [sizes] [langs] [scales]
set -euo pipefail
OUT=${1:?usage: tools/capture_ui_matrix.sh /absolute/out/dir}
SIZES=${2:-"1280x800 1600x900 2560x1440 3440x1440"}
LANGS=${3:-"pl en"}
SCALES=${4:-"0.75 1.0 1.5"}
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
for size in $SIZES; do
  for lang in $LANGS; do
    for scale in $SCALES; do
      dir="$OUT/${size}_${lang}_${scale}"
      echo "== $dir"
      "$GODOT" --path . tools/capture_ui.tscn -- --out="$dir" --size="$size" --lang="$lang" --scale="$scale" >/dev/null 2>&1 || echo "failed: $dir"
    done
  done
done
