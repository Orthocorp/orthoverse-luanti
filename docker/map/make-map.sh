#!/bin/sh
# Draw the map from /world/map.sqlite into /out (tiles/, lands/ and lands.json),
# then swap the new ones in at once. Safe while the server runs: it only reads.
#
#   make-map          draw now
#   make-map watch    redraw whenever the game has made the terrain of new lands
#                     (it writes /world/orthoverse_new_lands_made.json), checking
#                     every 5 minutes, and every night at OV_MAP_HOUR (UTC, default
#                     3), so that the token pictures show what holders have built
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
	python /app/web/map/make_tiles.py /world/map.sqlite /app/data/lands.json "$TMP" "$NEW_LANDS" \
		/chain/tokens.json /app/heraldry "$OUT/cards"
	rm -rf "$OUT/tiles.old"
	if [ -d "$OUT/tiles" ]; then mv "$OUT/tiles" "$OUT/tiles.old"; fi
	mv "$TMP/tiles" "$OUT/tiles"
	mv "$TMP/lands.json" "$OUT/lands.json"
	rm -rf "$OUT/lands.old"
	if [ -d "$OUT/lands" ]; then mv "$OUT/lands" "$OUT/lands.old"; fi
	mv "$TMP/lands" "$OUT/lands"
	rm -rf "$OUT/tiles.old" "$OUT/lands.old" "$TMP"
	echo "$(date -u +%FT%TZ) Map updated."
}

if [ "${1:-}" != watch ]; then
	draw
	exit
fi

HOUR="${OV_MAP_HOUR:-3}"
NIGHTLY="$OUT/.nightly"
echo "$(date -u +%FT%TZ) Watching for new lands; redrawing every night at $HOUR:00 UTC."
while :; do
	today=$(date -u +%F)
	if [ "$(date -u +%-H)" -eq "$HOUR" ] && [ "$(cat "$NIGHTLY" 2>/dev/null || true)" != "$today" ]; then
		echo "$(date -u +%FT%TZ) Nightly redraw."
		draw || true
		echo "$today" > "$NIGHTLY"
	fi
	# Newer than the map, and quiet for 2 minutes (the server saves blocks
	# every few seconds)
	if [ -f "$MADE" ] && { [ ! -f "$OUT/lands.json" ] || [ "$MADE" -nt "$OUT/lands.json" ]; } \
			&& [ $(( $(date +%s) - $(stat -c %Y "$MADE") )) -ge 120 ]; then
		echo "$(date -u +%FT%TZ) New lands have their terrain: redrawing the map."
		draw || true
	fi
	sleep 300
done
