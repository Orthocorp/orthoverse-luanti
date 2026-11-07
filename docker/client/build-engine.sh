#!/bin/bash
# Build the engine with the Orthoverse patches, its file system pack and the
# release files in www/. Run from /luanti-wasm by the client Dockerfile, with a
# build cache mounted at /cache.
#
# The engine's object files are kept in /cache/luanti, so after a patch changes
# only the changed files are recompiled. build_luanti.sh deletes its build
# directory unless it is incremental, so the cache is linked in only when it
# already holds a build of this same luanti-wasm commit; otherwise the engine is
# built in place and the result copied into the cache for next time.
set -euo pipefail
COMMIT="$1"

git -C sources/luanti reset -q --hard
for p in /patches/*.patch; do
	echo "patch: $(basename "$p")"
	git -C sources/luanti apply "$p"
done

rm -rf build/luanti
if [[ -f /cache/luanti/CMakeCache.txt && "$(cat /cache/commit 2>/dev/null || true)" == "$COMMIT" ]]; then
	echo "engine: incremental"
	ln -s /cache/luanti build/luanti
	INCREMENTAL=true ./build_luanti.sh
else
	echo "engine: full"
	INCREMENTAL=false ./build_luanti.sh
	rm -rf /cache/luanti /cache/commit
	cp -a build/luanti /cache/luanti
	echo "$COMMIT" > /cache/commit
fi

# Our own engine textures (web/client/textures/) over the engine's
PACK="build/luanti-install/textures/base/pack"
[[ -d "$PACK" ]] || { echo "No $PACK: the engine's install layout changed" >&2; exit 1; }
for t in /textures/*.png; do
	[[ -e "$t" ]] || continue
	echo "texture: $(basename "$t")"
	cp "$t" "$PACK/"
done

./build_fsroot.sh
./build_www.sh
# The object files stay in the cache, not in the image
rm -rf build/luanti
echo "engine: done"
