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

full_build() {
	echo "engine: full"
	rm -rf build/luanti
	INCREMENTAL=false ./build_luanti.sh
	rm -rf /cache/luanti /cache/commit
	cp -a build/luanti /cache/luanti
	echo "$COMMIT" > /cache/commit
}

# Emscripten builds its ports (SDL2, zlib, libpng...) into its own cache, in
# the image, the first time something links against them. A full build does
# that while CMake configures; an incremental one re-runs CMake against the
# saved configuration and needs them there already (when an earlier step of
# the image changed, Docker starts that cache afresh). So link a tiny program
# with the engine's flags and ports first.
warm_ports() {
	bash -c 'source ./common.sh
		cd "$(mktemp -d)"
		echo "int main(void) { return 0; }" > warm.c
		emcc $CFLAGS -sUSE_SDL=2 --use-port=zlib --use-port=libjpeg --use-port=libpng \
			--use-port=freetype --use-port=ogg --use-port=vorbis --use-port=sqlite3 \
			$LDFLAGS warm.c -o warm.js'
}

rm -rf build/luanti
if [[ -f /cache/luanti/CMakeCache.txt && "$(cat /cache/commit 2>/dev/null || true)" == "$COMMIT" ]]; then
	echo "engine: incremental"
	warm_ports || echo "engine: could not build the ports first"
	ln -s /cache/luanti build/luanti
	if ! INCREMENTAL=true ./build_luanti.sh; then
		# Whatever went wrong, a full build starts clean
		echo "engine: the incremental build failed; building in full"
		rm -f build/luanti
		full_build
	fi
else
	full_build
fi

# Our own engine textures (web/client/textures/) over the engine's
PACK="build/luanti-install/textures/base/pack"
[[ -d "$PACK" ]] || { echo "No $PACK: the engine's install layout changed" >&2; exit 1; }
for t in /textures/*.png; do
	[[ -e "$t" ]] || continue
	echo "texture: $(basename "$t")"
	cp "$t" "$PACK/"
done

# Our fonts (web/client/fonts/) in place of the engine's own, under the
# engine's file names, so its defaults pick them up wherever the browser game
# keeps its files: Alegreya for chat and text (as Arimo), Midnight for titles
# and buttons (as Cousine, the "mono" font that windows ask for by style)
FONTS="build/luanti-install/fonts"
[[ -d "$FONTS" ]] || { echo "No $FONTS: the engine's install layout changed" >&2; exit 1; }
for v in Regular Bold Italic BoldItalic; do
	cp /fonts/Alegreya.ttf "$FONTS/Arimo-$v.ttf"
	cp /fonts/midnight.ttf "$FONTS/Cousine-$v.ttf"
done
cp /fonts/Alegreya-OFL.txt "$FONTS/"
echo "fonts: Alegreya and Midnight"

./build_fsroot.sh
./build_www.sh
# The object files stay in the cache, not in the image
rm -rf build/luanti
echo "engine: done"
