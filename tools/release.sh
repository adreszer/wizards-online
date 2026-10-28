#!/usr/bin/env bash
# Builds a release: offline checks, the leak check for both platforms, both
# exports stamped with the version, zipped under export/release/<version>/,
# and (with --push) uploaded to itch.io with butler and tagged in git.
# Needs a clean tree and the Godot export templates.
# Usage: tools/release.sh <version> [--push]
#   ITCH_TARGET=<user>/<game> (default adreszer/arcane-academy) picks the itch.io page.
# Bump NetworkProtocol.PROTOCOL_VERSION first when the release changes what client and
# server send each other; deploy the server before pushing the clients.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-}"
PUSH="${2:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "usage: tools/release.sh <version, e.g. 0.2.0> [--push]" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "The tree has uncommitted changes; commit or set them aside first." >&2
  exit 1
fi
GODOT="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
export GODOT
ITCH_TARGET="${ITCH_TARGET:-adreszer/arcane-academy}"
OUT="export/release/$VERSION"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

step() { printf '\n== %s\n' "$1"; }

step "offline checks"
tools/check.sh

for preset in "Windows Desktop" macOS; do
  step "leak check ($preset)"
  tools/check_build.sh "$preset"
done

# Stamp the version into the project and the presets for the export only; the
# committed files are restored afterwards, whatever happens.
cp project.godot "$LOGS/project.godot.orig"
cp export_presets.cfg "$LOGS/export_presets.cfg.orig"
restore() {
  cp "$LOGS/project.godot.orig" project.godot
  cp "$LOGS/export_presets.cfg.orig" export_presets.cfg
}
trap restore EXIT
python3 -I - "$VERSION" <<'PY'
import re, sys
version = sys.argv[1]
numeric = ".".join((version.split(".") + ["0", "0", "0"])[:4])
text = open("project.godot").read()
if "config/version=" in text:
    text = re.sub(r'config/version="[^"]*"', f'config/version="{version}"', text)
else:
    text = text.replace('config/name="Arcane Academy"', f'config/name="Arcane Academy"\nconfig/version="{version}"')
open("project.godot", "w").write(text)
presets = open("export_presets.cfg").read()
presets = re.sub(r'application/(short_)?version="[^"]*"', lambda m: f'application/{m.group(1) or ""}version="{version}"', presets)
presets = re.sub(r'application/(file|product)_version="[^"]*"', lambda m: f'application/{m.group(1)}_version="{numeric}"', presets)
open("export_presets.cfg", "w").write(presets)
PY

step "export Windows"
mkdir -p "$OUT/windows"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/windows/ArcaneAcademy.exe" >"$LOGS/export_windows.log" 2>&1
[ -s "$OUT/windows/ArcaneAcademy.exe" ] || { echo "Windows export failed (log: $LOGS/export_windows.log)" >&2; exit 1; }

step "export macOS"
"$GODOT" --headless --path . --export-release macOS "$OUT/ArcaneAcademy-macos.zip" >"$LOGS/export_macos.log" 2>&1
[ -s "$OUT/ArcaneAcademy-macos.zip" ] || { echo "macOS export failed (log: $LOGS/export_macos.log)" >&2; exit 1; }

restore
trap - EXIT
(cd "$OUT/windows" && zip -qr "../ArcaneAcademy-windows.zip" .)
du -h "$OUT"/*.zip

if [ "$PUSH" != "--push" ]; then
  echo "release $VERSION built in $OUT (add --push to upload to itch.io and tag)"
  exit 0
fi
command -v butler >/dev/null || { echo "butler not found (https://itch.io/docs/butler/)" >&2; exit 1; }
step "upload to itch.io ($ITCH_TARGET)"
butler push "$OUT/windows" "$ITCH_TARGET:windows" --userversion "$VERSION"
butler push "$OUT/ArcaneAcademy-macos.zip" "$ITCH_TARGET:mac" --userversion "$VERSION"
git tag -a "v$VERSION" -m "Arcane Academy $VERSION"
git push origin "v$VERSION"
echo "release $VERSION pushed"
