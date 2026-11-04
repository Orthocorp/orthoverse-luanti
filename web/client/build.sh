#!/usr/bin/env bash
# Build the in-browser Luanti client (paradust7/luanti-wasm) with the
# Orthoverse play page, and install it where nginx serves /play/.
#
#   sudo -u ovserver ./build.sh               # on the ProLiant, after install-web.sh
#
# Takes about 15 to 30 minutes on the ProLiant the first time (it downloads and
# sets up the Emscripten SDK, about 3 GB) and less on later builds.
# Needs: build-essential cmake tclsh python3 git zip zstd gettext wget xz-utils
# (install-web.sh installs them).
set -euo pipefail

BASE="${BASE:-/mnt/ethereum/orthoverse}"
WORK="${WORK:-$BASE/build}"
OUT="${OUT:-$BASE/web/play}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Pinned versions (tested together, 4 Nov 2026)
LUANTI_WASM_REPO="https://github.com/paradust7/luanti-wasm.git"
LUANTI_WASM_COMMIT="5bfae52b53605b39667dfc29cddd59c861e38111"   # 17 Oct 2026, Luanti 5.18
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
git -C "$SRC" -c advice.detachedHead=false checkout -q "$LUANTI_WASM_COMMIT"

# Our deploy hook: build_www.sh runs ./deploy.sh <release id> at the end.
cp "$HERE/deploy.sh" "$SRC/deploy.sh"
cp "$HERE/play.html" "$SRC/orthoverse-play.html"
chmod +x "$SRC/deploy.sh"

cd "$SRC"
if [[ ! -d emsdk ]]; then
	echo "== Setting up the Emscripten SDK (first build only)"
	./install_emsdk.sh
fi

echo "== Building (this is the long part)"
./build_all.sh > "$WORK/build.log" 2>&1 || {
	echo "Build failed; the last lines of $WORK/build.log:"
	tail -n 40 "$WORK/build.log"
	exit 1
}

echo "== Installing into $OUT"
mkdir -p "$OUT"
# Keep the previous release next to the new one until browsers have moved on;
# index.html always points at the newest.
rsync -a "$SRC/www/" "$OUT/"
release=$(cat "$SRC/www/RELEASE")
# Remove releases older than the two newest
ls -1dt "$OUT"/*/ | grep -v "/$release/" | tail -n +2 | xargs -r rm -rf
echo "Installed release $release. Players load it from /play/."
