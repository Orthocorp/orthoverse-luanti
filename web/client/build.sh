#!/usr/bin/env bash
# Build the in-browser Luanti client (paradust7/luanti-wasm) with the
# Orthoverse play page, and install it where nginx serves /play/.
#
#   sudo -u ovserver ./build.sh               # on the ProLiant, after install-web.sh
#   sudo -u ovserver PAGE=1 ./build.sh        # only play.html changed: seconds
#   sudo -u ovserver FULL=1 ./build.sh        # rebuild everything from scratch
#
# Three kinds of build, chosen automatically:
#   full    the support libraries (zstd, libarchive, openssl, curl, ...) and the
#           engine. 15 to 30 minutes. Only the first time, after the pinned
#           luanti-wasm commit changes, or with FULL=1.
#   engine  recompiles only what changed in the engine (our patches, usually)
#           and packages a new release. A few minutes.
#   page    PAGE=1: no compiling; installs play.html for the current release.
# Needs: build-essential cmake tclsh python3 git zip zstd gettext wget xz-utils
# (install-web.sh installs them).
set -euo pipefail

BASE="${BASE:-/mnt/ethereum/orthoverse}"
WORK="${WORK:-$BASE/build}"
OUT="${OUT:-$BASE/web/play}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Pinned versions (tested together, 4 Nov 2026)
LUANTI_WASM_REPO="${LUANTI_WASM_REPO:-https://github.com/paradust7/luanti-wasm.git}"
LUANTI_WASM_COMMIT="${LUANTI_WASM_COMMIT:-5bfae52b53605b39667dfc29cddd59c861e38111}"   # 17 Oct 2026, Luanti 5.18
NODE_VERSION="v24.22.0"                                          # luanti-wasm needs Node 24

mkdir -p "$WORK"
cd "$WORK"

# Node 24, shared with the web proxy (install-web.sh puts it in $BASE/node);
# nothing on the system changes
NODE_DIR="${NODE_DIR:-$BASE/node}"
if [[ "$("$NODE_DIR/bin/node" --version 2>/dev/null || true)" != "$NODE_VERSION" ]]; then
	echo "Node $NODE_VERSION not found in $NODE_DIR: run tools/proliant/install-web.sh first." >&2
	exit 1
fi
export PATH="$NODE_DIR/bin:$PATH"
node --version

echo "== luanti-wasm at ${LUANTI_WASM_COMMIT:0:7}"
SRC="$WORK/luanti-wasm"
if [[ ! -d "$SRC/.git" ]]; then
	git clone -q "$LUANTI_WASM_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin
# -f: drop the local changes below from a previous run, so they apply once
git -C "$SRC" -c advice.detachedHead=false checkout -q -f "$LUANTI_WASM_COMMIT"

# Emscripten 6 builds real shared libraries. zstd and libzip build a .so next
# to their .a, the linker then prefers libzstd.so, and the test programs that
# libarchive's configure runs fail to load it ("cannot compute sizeof
# (wchar_t)"). Build those two as static libraries only.
for f in build_zstd.sh build_libzip.sh; do
	sed -i '/^emcmake cmake \\$/a\  -DBUILD_SHARED_LIBS=OFF -DZSTD_BUILD_SHARED=OFF \\' "$SRC/$f"
	grep -q -- '-DBUILD_SHARED_LIBS=OFF' "$SRC/$f" || { echo "Could not patch $f" >&2; exit 1; }
done

# Our deploy hook: build_www.sh runs ./deploy.sh <release id> at the end.
cp "$HERE/deploy.sh" "$SRC/deploy.sh"
cp "$HERE/play.html" "$SRC/orthoverse-play.html"
chmod +x "$SRC/deploy.sh"

cd "$SRC"

# Bump when a change here needs the libraries rebuilt (it forces a full build)
DEPS_VERSION=1
STAMP="$WORK/full-build.stamp"
STAMP_WANT="$LUANTI_WASM_COMMIT deps-$DEPS_VERSION"

if [[ "${PAGE:-0}" == 1 ]]; then
	release=$(cat www/RELEASE 2>/dev/null || true)
	if [[ -z "$release" || ! -d "$OUT/$release" ]]; then
		echo "No installed release to put the page on: run a normal build first." >&2
		exit 1
	fi
	echo "== Page only, for release $release"
	./deploy.sh "$release"
	install -m 644 www/index.html "$OUT/index.html"
	echo "Installed play.html. Players get it on their next page load."
	exit 0
fi
if [[ ! -d emsdk ]]; then
	echo "== Setting up the Emscripten SDK (first build only)"
	./install_emsdk.sh
fi

# Orthoverse changes to the engine itself (web/client/patches): the sources are
# fetched first so they can be patched; the build then finds them in place.
# reset --hard drops a previous run's patches without moving off the pinned
# revision, which the build checks.
echo "== Patching the engine"
./fetch_sources.sh > "$WORK/fetch.log" 2>&1 || {
	echo "Fetching sources failed; the last lines of $WORK/fetch.log:"
	tail -n 20 "$WORK/fetch.log"
	exit 1
}
# Only touch the engine sources when the patches changed: re-applying them
# would make every build recompile the patched files.
patch_sum=$(cat "$HERE"/patches/*.patch | sha256sum | cut -c1-16)
if [[ "$(cat sources/luanti/.orthoverse-patches 2>/dev/null || true)" == "$patch_sum" ]]; then
	echo "   unchanged since the last build"
else
	git -C sources/luanti reset -q --hard
	for p in "$HERE"/patches/*.patch; do
		echo "   $(basename "$p")"
		git -C sources/luanti apply "$p"
	done
	echo "$patch_sum" > sources/luanti/.orthoverse-patches
fi

# Full or engine-only? Engine-only needs the libraries and the engine's build
# setup from an earlier full build of this same commit.
libs_ok=1
for f in build/install/lib/libarchive.a build/install/lib/libzip.a build/install/lib/libzstd.a \
		build/install/lib/libcurl.a build/install/lib/libssl.a build/luanti/CMakeCache.txt www/RELEASE; do
	[[ -e "$f" ]] || libs_ok=0
done
if [[ ! -f "$STAMP" && $libs_ok == 1 ]]; then
	# Built before this script kept a stamp; the pin has not moved since.
	echo "$STAMP_WANT" > "$STAMP"
fi
if [[ "${FULL:-0}" == 1 || $libs_ok == 0 || "$(cat "$STAMP" 2>/dev/null || true)" != "$STAMP_WANT" ]]; then
	echo "== Full build: libraries and engine (15 to 30 minutes)"
	rm -f "$STAMP"
	./build_all.sh > "$WORK/build.log" 2>&1 || {
		echo "Build failed; the last lines of $WORK/build.log:"
		tail -n 40 "$WORK/build.log"
		exit 1
	}
	echo "$STAMP_WANT" > "$STAMP"
else
	echo "== Engine-only build (libraries already built)"
	./incremental.sh > "$WORK/build.log" 2>&1 || {
		echo "Build failed; the last lines of $WORK/build.log:"
		tail -n 40 "$WORK/build.log"
		echo "If this keeps failing, try a clean build: FULL=1" >&2
		exit 1
	}
fi

echo "== Installing into $OUT"
mkdir -p "$OUT"
# Keep the previous release next to the new one until browsers have moved on;
# index.html always points at the newest.
rsync -a "$SRC/www/" "$OUT/"
release=$(cat "$SRC/www/RELEASE")
# Remove releases older than the two newest
ls -1dt "$OUT"/*/ | { grep -v "/$release/" || true; } | tail -n +2 | xargs -r rm -rf
echo "Installed release $release. Players load it from /play/."
