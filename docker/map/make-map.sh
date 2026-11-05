#!/bin/sh
# Draw the map from /world/map.sqlite into /out (tiles/ and lands.json), then
# swap the new tiles in at once. Safe while the server runs: it only reads.
set -eu
OUT=/out
TMP="$OUT/.new"
if [ ! -f /world/map.sqlite ]; then
	echo "No map in the world yet (/world/map.sqlite): generate it first." >&2
	exit 1
fi
rm -rf "$TMP"
mkdir -p "$TMP"
python /app/web/map/make_tiles.py /world/map.sqlite /app/data/lands.json "$TMP"
rm -rf "$OUT/tiles.old"
if [ -d "$OUT/tiles" ]; then mv "$OUT/tiles" "$OUT/tiles.old"; fi
mv "$TMP/tiles" "$OUT/tiles"
mv "$TMP/lands.json" "$OUT/lands.json"
rm -rf "$OUT/tiles.old" "$TMP"
echo "Map updated."
