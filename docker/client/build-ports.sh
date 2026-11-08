#!/bin/bash
# Build Emscripten's ports (SDL2, zlib, libjpeg, libpng, freetype, ogg, vorbis,
# sqlite3) with the engine's flags. Run from /luanti-wasm.
#
# Emscripten downloads and builds a port the first time something is compiled
# with it, and the engine's CMake needs SDL2's files (sdl2-config.cmake) in
# place before it configures: if they are missing, every test compile fails
# and CMake stops with "Could not find a package configuration file provided
# by SDL2". The client Dockerfile runs this in its own layer, so engine builds
# never depend on those downloads; build-engine.sh runs it again as a check.
# Emscripten downloads each port once, from one address, so fetch-ports
# downloads them first, with retries and second addresses where they exist.
set -uo pipefail

fetch-ports || exit 1

SDL2_CMAKE="emsdk/upstream/emscripten/cache/sysroot/lib/cmake/SDL2/sdl2-config.cmake"

build() {
	bash -c 'source ./common.sh
		cd "$(mktemp -d)"
		echo "int main(void) { return 0; }" > ports.c
		emcc $CFLAGS -sUSE_SDL=2 --use-port=zlib --use-port=libjpeg --use-port=libpng \
			--use-port=freetype --use-port=ogg --use-port=vorbis --use-port=sqlite3 \
			$LDFLAGS ports.c -o ports.js'
}

for try in 1 2 3; do
	if build && [[ -f "$SDL2_CMAKE" ]]; then
		echo "ports: ready"
		exit 0
	fi
	echo "ports: attempt $try failed"
	sleep $((try * 20))
done
echo "ports: could not build Emscripten's ports (see the errors above; a download from GitHub or storage.googleapis.com failing is the usual cause)" >&2
exit 1
