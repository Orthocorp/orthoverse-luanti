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
	# Each drawing goes in its own folder, tiles/<version>/, named in
	# lands.json: the map page asks for that version's tiles, so a redraw shows
	# at once whatever Cloudflare or a browser has cached
	version=$(date -u +%Y%m%d%H%M%S)
	rm -rf "$TMP"
	mkdir -p "$TMP" "$OUT/tiles"
	MAP_VERSION="$version" python /app/web/map/make_tiles.py /world/map.sqlite /app/data/lands.json "$TMP" "$NEW_LANDS" \
		/chain/tokens.json /app/heraldry "$OUT/cards"
	mv "$TMP/tiles" "$OUT/tiles/$version"
	mv "$TMP/lands.json" "$OUT/lands.json"
	rm -rf "$OUT/lands.old"
	if [ -d "$OUT/lands" ]; then mv "$OUT/lands" "$OUT/lands.old"; fi
	mv "$TMP/lands" "$OUT/lands"
	rm -rf "$OUT/lands.old" "$TMP" "$OUT/tiles.old"
	# Keep this drawing and the one before (for pages loaded a moment ago);
	# remove older ones, and the tiles from before versions (tiles/0 .. tiles/6)
	for d in "$OUT"/tiles/*; do
		case "${d##*/}" in ?) rm -rf "$d" ;; esac
	done
	ls -1d "$OUT"/tiles/2*/ 2>/dev/null | sort -r | tail -n +3 | xargs -r rm -rf
	echo "$(date -u +%FT%TZ) Map updated (version $version)."
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
