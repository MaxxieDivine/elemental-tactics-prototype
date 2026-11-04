#!/usr/bin/env bash
# Builds the single-threaded web export into build/web (used by CI too).
# Usage: tools/build_web.sh [path-to-godot]
set -euo pipefail
GODOT="${1:-godot}"
OUT=build/web
rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"
test -f "$OUT/index.wasm"
# Let the canvas extend under the notch / gesture bar; the game reads the
# safe-area insets itself and keeps its UI inside them.
sed -i 's/initial-scale=1.0"/initial-scale=1.0, viewport-fit=cover"/' "$OUT/index.html"
grep -q 'viewport-fit=cover' "$OUT/index.html"
grep -q 'name="robots" content="noindex' "$OUT/index.html"
printf 'User-agent: *\nDisallow: /\n' > "$OUT/robots.txt"
touch "$OUT/.nojekyll"
echo "Web build ready in $OUT"
