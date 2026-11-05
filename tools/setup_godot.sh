#!/usr/bin/env bash
# Installs the project's exact Godot version (and, with --web, its no-threads
# web export templates) when they are missing. Safe to run every session:
# it does nothing if the right version is already installed.
# Usage: tools/setup_godot.sh [--web]
# Installs to $GODOT_BIN_DIR (default ~/.local/bin) as `godot`.
set -euo pipefail
cd "$(dirname "$0")/.."
# The version CI uses is the single source of truth.
VERSION="$(sed -n 's/^ *GODOT_VERSION: *"\([^"]*\)".*/\1/p' .github/workflows/ci.yml | head -n1)"
VERSION="${VERSION:-4.3}"
BIN_DIR="${GODOT_BIN_DIR:-$HOME/.local/bin}"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

have_godot() {
	local g
	g="$(command -v godot 2>/dev/null || true)"
	[ -n "$g" ] && "$g" --version 2>/dev/null | grep -q "^${VERSION}\.stable"
}

if have_godot; then
	echo "Godot ${VERSION} already installed: $(command -v godot)"
else
	echo "Installing Godot ${VERSION} to ${BIN_DIR}..."
	mkdir -p "$BIN_DIR"
	curl -fsSL -o "$TMP/godot.zip" "$BASE/Godot_v${VERSION}-stable_linux.x86_64.zip"
	unzip -q "$TMP/godot.zip" -d "$TMP"
	install -m 755 "$TMP/Godot_v${VERSION}-stable_linux.x86_64" "$BIN_DIR/godot"
	case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Note: add $BIN_DIR to PATH (export PATH=\"$BIN_DIR:\$PATH\")." ;; esac
	"$BIN_DIR/godot" --version
fi

if [ "${1:-}" = "--web" ]; then
	TPL="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
	if [ -f "$TPL/web_nothreads_release.zip" ] && [ -f "$TPL/web_nothreads_debug.zip" ]; then
		echo "Web export templates already installed: $TPL"
	else
		echo "Installing Godot ${VERSION} web export templates..."
		mkdir -p "$TPL"
		curl -fsSL -o "$TMP/templates.tpz" "$BASE/Godot_v${VERSION}-stable_export_templates.tpz"
		unzip -q -j "$TMP/templates.tpz" templates/web_nothreads_release.zip templates/web_nothreads_debug.zip templates/version.txt -d "$TPL"
	fi
fi
