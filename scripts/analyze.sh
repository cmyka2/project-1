#!/usr/bin/env bash
# Strict type-check of all game code against the Roblox API definitions.
# Requires rojo and luau-lsp on PATH (rokit install), downloads type defs once.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tools
DEFS=.tools/globalTypes.d.luau
if [ ! -f "$DEFS" ]; then
  curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.38.0/scripts/globalTypes.d.luau
fi
ROJO=${ROJO:-rojo}
LUAU_LSP=${LUAU_LSP:-luau-lsp}
"$ROJO" sourcemap default.project.json -o sourcemap.json
"$LUAU_LSP" analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=.luaurc \
  --ignore="tests/**" src
