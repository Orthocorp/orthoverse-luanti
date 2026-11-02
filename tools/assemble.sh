#!/usr/bin/env bash
# Pull Minetest Game's mods into mods/mtg (a modpack) so the game is self-contained.
# Usage: tools/assemble.sh [minetest_game git ref]   (default: the commit tested below)
set -euo pipefail
REF="${1:-9e895af}"
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
git clone -q https://github.com/luanti-org/minetest_game.git "$tmp/mtg"
git -C "$tmp/mtg" checkout -q "$REF"
rm -rf mods/mtg
mkdir -p mods/mtg
cp -r "$tmp/mtg/mods/"* mods/mtg/
printf 'name = mtg\ndescription = Minetest Game mods (vendored, %s)\n' "$REF" > mods/mtg/modpack.conf
cp "$tmp/mtg/LICENSE.txt" mods/mtg/LICENSE-minetest_game.txt 2>/dev/null || true
rm -rf "$tmp"
echo "Minetest Game mods copied into mods/mtg at $REF"
