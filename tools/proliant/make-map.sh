#!/usr/bin/env bash
# Render the web map (tiles and land list) from the live world.
# Safe while the server runs: it only reads the map database.
#   sudo -u ovserver /mnt/ethereum/orthoverse/make-map.sh
set -euo pipefail
BASE="${BASE:-/mnt/ethereum/orthoverse}"
GAME="$BASE/game"
WORLD="$BASE/luanti/worlds/orthoverse"
OUT="$BASE/web/site/map"
TMP="$OUT.new"
rm -rf "$TMP"
mkdir -p "$TMP"
"$BASE/venv/bin/python" "$GAME/web/map/make_tiles.py" "$WORLD/map.sqlite" \
	"$GAME/mods/orthoverse_lands/data/lands.json" "$TMP"
# Swap the new tiles in at once
rm -rf "$OUT/tiles.old"
[[ -d "$OUT/tiles" ]] && mv "$OUT/tiles" "$OUT/tiles.old"
mv "$TMP/tiles" "$OUT/tiles"
mv "$TMP/lands.json" "$OUT/lands.json"
rm -rf "$OUT/tiles.old" "$TMP"
echo "Map updated in $OUT"
