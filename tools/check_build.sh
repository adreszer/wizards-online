#!/usr/bin/env bash
# Release leak check: exports the client pack with the committed preset and
# fails if server content or dev-only files are inside, or if any server-only
# text (nakama/content/strings.json keys and texts, mystery ids) appears in
# its bytes. Needs the Godot export templates (Editor → Manage Export
# Templates). Usage: tools/check_build.sh ["Windows Desktop" | macOS]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
PRESET="${1:-Windows Desktop}"
OUT=export/check
mkdir -p "$OUT"
rm -f "$OUT/client.pck"
echo "== export pack ($PRESET)"
if ! "$GODOT" --headless --path . --export-pack "$PRESET" "$OUT/client.pck" >"$OUT/export.log" 2>&1 || [ ! -s "$OUT/client.pck" ]; then
  grep -iE "template|error" "$OUT/export.log" | head -5 >&2 || true
  echo "FAILED: export (are the export templates installed?) — log: $OUT/export.log" >&2
  exit 1
fi
echo "== leak check"
python3 -I - "$OUT/client.pck" <<'PY'
import json, os, sys
sys.path.insert(0, os.path.join(os.getcwd(), "tools"))
from list_pck import list_pck

pck = sys.argv[1]
problems = []
files = list_pck(pck)
for path in files:
    rel = path[len("res://"):]
    if rel.split("/")[0] in ("nakama", "tools", "tests", "docs") or rel.startswith("levels/dev/") or rel.startswith("levels/mvp/"):
        problems.append("dev/server file in the pack: " + path)
    if rel.startswith("content/") and rel != "content/offline_mysteries.json":
        problems.append("unexpected content file: " + path)
needles = {}
strings = json.load(open("nakama/content/strings.json"))
for key, entry in strings.items():
    needles[key] = "strings.json key"
    for loc, text in entry.items():
        if len(text) >= 12:
            needles[text] = f"strings.json {key}.{loc}"
for m in json.load(open("nakama/content/mysteries.json")).get("mysteries", []):
    needles[m["id"]] = "mystery id"
data = open(pck, "rb").read()
for needle, what in needles.items():
    raw = needle.encode("utf-8")
    at = data.find(raw)
    # A server key inside a longer public key (OFFLINE_MYST_…) is not a leak.
    while at > 0 and (chr(data[at - 1]).isalnum() or data[at - 1] == ord("_")):
        at = data.find(raw, at + 1)
    if at >= 0:
        problems.append(f"{what} found in the pack: {needle[:40]!r}")
print(f"{len(files)} files, {len(needles)} server strings checked")
for p in problems:
    print("LEAK:", p)
sys.exit(1 if problems else 0)
PY
echo "build leak check passed"
