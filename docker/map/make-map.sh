#!/bin/sh
# Draw the map from /world/map.sqlite into /out (tiles/ and lands.json), then
# swap the new tiles in at once. Safe while the server runs: it only reads.
#
#   make-map          draw now
#   make-map watch    redraw whenever the game has made the terrain of new lands
#                     (it writes /world/orthoverse_new_lands_made.json), checking
#                     every 5 minutes
set -eu
OUT=/out
TMP="$OUT/.new"
NEW_LANDS=/chain/new-lands.json
MADE=/world/orthoverse_new_lands_made.json

draw() {
	if [ ! -f /world/map.sqlite ]; then
		echo "No map in the world yet (/world/map.sqlite): generate it first." >&2
		return 1
	fi
	rm -rf "$TMP"
	mkdir -p "$TMP"
	python /app/web/map/make_tiles.py /world/map.sqlite /app/data/lands.json "$TMP" "$NEW_LANDS"
	rm -rf "$OUT/tiles.old"
	if [ -d "$OUT/tiles" ]; then mv "$OUT/tiles" "$OUT/tiles.old"; fi
	mv "$TMP/tiles" "$OUT/tiles"
	mv "$TMP/lands.json" "$OUT/lands.json"
	rm -rf "$OUT/tiles.old" "$TMP"
	echo "$(date -u +%FT%TZ) Map updated."
}

if [ "${1:-}" != watch ]; then
	draw
	exit
fi

echo "$(date -u +%FT%TZ) Watching for new lands."
while :; do
	# Newer than the map, and quiet for 2 minutes (the server saves blocks
	# every few seconds)
	if [ -f "$MADE" ] && { [ ! -f "$OUT/lands.json" ] || [ "$MADE" -nt "$OUT/lands.json" ]; } \
			&& [ $(( $(date +%s) - $(stat -c %Y "$MADE") )) -ge 120 ]; then
		echo "$(date -u +%FT%TZ) New lands have their terrain: redrawing the map."
		draw || true
	fi
	sleep 300
done
