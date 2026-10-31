#!/usr/bin/env bash
# Compiles the island's fragment shaders to .qsb (needs qt6-shadertools).
set -euo pipefail
QSB="${QSB:-$(command -v qsb || echo /usr/lib/qt6/bin/qsb)}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../quickshell/island/core/shaders" && pwd)"
for f in "$DIR"/*.frag; do
  "$QSB" --qt6 -o "$f.qsb" "$f"
  echo "built ${f##*/}.qsb"
done
