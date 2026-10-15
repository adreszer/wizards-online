#!/usr/bin/env bash
# Run Godot headless with a time limit (a script parse error otherwise leaves it running).
# Usage: tools/godot_timeout.sh SECONDS LOGFILE <godot args…>
secs=$1; log=$2; shift 2
exec perl -e 'alarm shift; exec @ARGV' "$secs" "${GODOT:-godot}" --headless --path . "$@" >"$log" 2>&1
