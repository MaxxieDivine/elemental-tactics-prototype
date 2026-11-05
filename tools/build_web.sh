#!/usr/bin/env bash
# Builds the single-threaded web export into build/web (used by CI too).
# Usage: tools/build_web.sh [path-to-godot]
set -euo pipefail
GODOT="${1:-godot}"
OUT=build/web
rm -rf "$OUT"
mkdir -p "$OUT"
# Stamp the build so the start screen shows which version a phone is running.
SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo dev)}"
SHA="${SHA:0:7}"
printf '{ "build": "%s", "date": "%s" }\n' "$SHA" "$(date -u +%Y-%m-%d)" > data/build.json
trap 'rm -f data/build.json' EXIT
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"
test -f "$OUT/index.wasm"
# Load the game files with the build id in the URL, so a phone that still has
# an older index.pck / index.js cached fetches this build's files instead.
sed -i "s|\"executable\":\"index\",|\"executable\":\"index\",\"mainPack\":\"index.pck?v=$SHA\",|" "$OUT/index.html"
sed -i "s|src=\"index.js\"|src=\"index.js?v=$SHA\"|" "$OUT/index.html"
grep -q "index.pck?v=$SHA" "$OUT/index.html"
grep -q "index.js?v=$SHA" "$OUT/index.html"
# Let the canvas extend under the notch / gesture bar; the game reads the
# safe-area insets itself and keeps its UI inside them.
sed -i 's/initial-scale=1.0"/initial-scale=1.0, viewport-fit=cover"/' "$OUT/index.html"
grep -q 'viewport-fit=cover' "$OUT/index.html"
grep -q 'name="robots" content="noindex' "$OUT/index.html"
printf 'User-agent: *\nDisallow: /\n' > "$OUT/robots.txt"
touch "$OUT/.nojekyll"
echo "Web build ready in $OUT"
