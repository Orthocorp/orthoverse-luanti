#!/bin/sh
# Install the built browser game into /out (served at /play/): the release
# files, and the Orthoverse play page pointing at them. The newest two
# releases are kept, so players halfway through loading are not broken.
set -eu
WWW=/luanti-wasm/www
OUT=/out

release=$(cd "$WWW" && ls -d */ | head -n 1 | tr -d /)
if [ -z "$release" ]; then
	echo "No release in $WWW: the image build did not finish." >&2
	exit 1
fi

rsync -a "$WWW/$release" "$OUT/"
sed "s/%__RELEASE_UUID__%/$release/g" /luanti-wasm/orthoverse-play.html > "$OUT/index.html.new"
mv "$OUT/index.html.new" "$OUT/index.html"
echo "$release" > "$OUT/RELEASE"

# Keep this release and the newest other one
ls -1dt "$OUT"/*/ | { grep -v "/$release/" || true; } | tail -n +2 | xargs -r rm -rf
echo "Installed release $release. Players get it on their next page load."
