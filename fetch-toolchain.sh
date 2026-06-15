#!/usr/bin/env bash
# Fetch the Nim->WASM toolchain (~70 MB) that unitcalc.html needs to recompile
# its engine in the browser. It mirrors the static assets from the open-source
# benagastov/Nim-WASM-Compiler demo into ./toolchain.
#
#   toolchain/
#     nim/   nim-bundle.js  nim.wasm  nimbase.h
#     clang/ clang.js  clang.wasm  lld.wasm  memfs.wasm  sysroot.tar
#
# Usage:  ./fetch-toolchain.sh
set -euo pipefail

REPO="https://github.com/benagastov/Nim-WASM-Compiler.git"
DEST="$(cd "$(dirname "$0")" && pwd)/toolchain"

if [ -f "$DEST/nim/nim-bundle.js" ] && [ -f "$DEST/clang/clang.js" ]; then
  echo "toolchain already present at $DEST - nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning toolchain (shallow)…"
git clone --depth 1 "$REPO" "$TMP/repo"

SRC="$TMP/repo/demo/static"
if [ ! -d "$SRC/nim" ] || [ ! -d "$SRC/clang" ]; then
  echo "error: expected toolchain assets not found in $SRC" >&2
  exit 1
fi

echo "Installing into $DEST …"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/nim" "$DEST/nim"
cp -R "$SRC/clang" "$DEST/clang"

echo
echo "Done. Toolchain installed:"
du -sh "$DEST" 2>/dev/null || true
echo
echo "Now serve this folder over http (file:// will not work):"
echo "    python3 -m http.server 8000"
echo "    open http://localhost:8000/unitcalc.html"
