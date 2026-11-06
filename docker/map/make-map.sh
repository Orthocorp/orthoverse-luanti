#!/bin/sh
# The web map, the land pictures and the token cards, from /world/map.sqlite
# into /out. Safe while the server runs: it only reads, a little at a time.
#
#   make-map          draw everything (about 10 minutes): after the world has
#                     been generated again, or the card design has changed
#   make-map update   draw again only the lands that changed: blocks placed or
#                     dug, lands made again or added (the game lists them in
#                     /world/orthoverse_changed_lands.json), and cards whose
#                     level or crest changed on the chain. Seconds per land
#   make-map watch    update every 5 minutes (the mapwatch service)
#
# Each drawing of the tiles is its own folder, tiles/<version>/, named in
# lands.json: the map page asks for that version's tiles, so a redraw shows at
# once whatever Cloudflare or a browser has cached. An update makes a new
# version out of hard links to the current one, so it costs next to nothing.
set -eu
OUT=/out
TMP="$OUT/.new"
ARGS="/world/map.sqlite /app/data/lands.json /chain/new-lands.json /chain/tokens.json /app/heraldry"
CHANGES=/world/orthoverse_changed_lands.json

check_world() {
	if [ ! -f /world/map.sqlite ]; then
		echo "No map in the world yet (/world/map.sqlite): generate it first." >&2
		return 1
	fi
}

draw() {
	check_world || return 1
	version=$(date -u +%Y%m%d%H%M%S)
	rm -rf "$TMP"
	mkdir -p "$TMP" "$OUT/tiles"
	# shellcheck disable=SC2086
	MAP_VERSION="$version" CARDS_DIR="$OUT/cards" STATE_DIR="$OUT" \
		python /app/web/map/make_tiles.py draw $ARGS "$TMP"
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

update() {
	check_world || return 1
	# shellcheck disable=SC2086
	python /app/web/map/make_tiles.py update $ARGS "$OUT" "$CHANGES"
}

case "${1:-}" in
	"") draw ;;
	update) update ;;
	watch)
		echo "$(date -u +%FT%TZ) Watching for changed lands every 5 minutes."
		while :; do
			update || true
			sleep 300
		done
		;;
	*) echo "make-map [update | watch]" >&2; exit 2 ;;
esac
