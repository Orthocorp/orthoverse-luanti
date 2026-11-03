#!/usr/bin/env bash
# Install the Orthoverse Luanti server on the ProLiant (Ubuntu 22.04).
#
#   sudo ./install.sh                # build Luanti, set up the game, world and service
#
# What it does (safe to re-run):
#   1. installs build dependencies with apt
#   2. creates a system user 'orthoverse' whose home is on the NVMe array
#   3. builds a server-only LuaJIT build of Luanti (tag below) in that home
#   4. links this repo in as the game 'orthoverse' and creates the world
#   5. installs a systemd service pinned to NUMA node 0, but does NOT start it
#
# Afterwards: pre-generate the map with ./pregen.sh, then
#   sudo systemctl enable --now orthoverse
#
# Nothing here opens ports on the router or changes the firewall.
set -euo pipefail

LUANTI_TAG="${LUANTI_TAG:-5.18.0}"
# Ubuntu 22.04's packaged LuaJIT (2017) is too old for Luanti 5.18, so build it
# from the LuaJIT v2.1 branch at a pinned commit (tested 3 Nov 2026).
LUAJIT_COMMIT="${LUAJIT_COMMIT:-ea9eb7e}"
BASE="${BASE:-/mnt/ethereum/orthoverse}"     # NVMe array
SVC_USER="${SVC_USER:-orthoverse}"
PORT="${PORT:-30000}"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ $EUID -ne 0 ]]; then
	echo "Run with sudo." >&2
	exit 1
fi

echo "== 1. Build dependencies"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
	git cmake g++ make libsqlite3-dev zlib1g-dev libzstd-dev \
	libcurl4-openssl-dev libgmp-dev libjsoncpp-dev libpq-dev libssl-dev sqlite3 rsync

echo "== 2. Service user and directories under $BASE"
if ! id "$SVC_USER" >/dev/null 2>&1; then
	useradd --system --home-dir "$BASE" --shell /usr/sbin/nologin "$SVC_USER"
fi
mkdir -p "$BASE" "$BASE/backups"
chown "$SVC_USER:$SVC_USER" "$BASE" "$BASE/backups"

GIT=(sudo -u "$SVC_USER" git -c advice.detachedHead=false)

echo "== 3a. Build LuaJIT $LUAJIT_COMMIT (static, linked into the server)"
LJ_SRC="$BASE/luajit-src"
LJ="$BASE/luajit"
if [[ ! -d "$LJ_SRC/.git" ]]; then
	"${GIT[@]}" clone -q -b v2.1 https://github.com/LuaJIT/LuaJIT.git "$LJ_SRC"
else
	"${GIT[@]}" -C "$LJ_SRC" fetch -q origin
fi
"${GIT[@]}" -C "$LJ_SRC" checkout -q "$LUAJIT_COMMIT"
sudo -u "$SVC_USER" make -s -C "$LJ_SRC" clean >/dev/null
sudo -u "$SVC_USER" make -s -C "$LJ_SRC" -j"$(nproc)" PREFIX="$LJ" amalg >/dev/null
sudo -u "$SVC_USER" make -s -C "$LJ_SRC" PREFIX="$LJ" install >/dev/null

echo "== 3b. Build Luanti $LUANTI_TAG (server only)"
SRC="$BASE/luanti"
if [[ ! -d "$SRC/.git" ]]; then
	"${GIT[@]}" clone -q --depth 1 -b "$LUANTI_TAG" \
		https://github.com/luanti-org/luanti.git "$SRC"
else
	"${GIT[@]}" -C "$SRC" fetch -q --depth 1 origin tag "$LUANTI_TAG"
	"${GIT[@]}" -C "$SRC" checkout -q "$LUANTI_TAG"
fi
sudo -u "$SVC_USER" cmake -S "$SRC" -B "$SRC/build" -DBUILD_CLIENT=0 -DBUILD_SERVER=1 \
	-DRUN_IN_PLACE=1 -DENABLE_LUAJIT=1 -DENABLE_POSTGRESQL=1 -DENABLE_LEVELDB=0 \
	-DLUA_INCLUDE_DIR="$LJ/include/luajit-2.1" -DLUA_LIBRARY="$LJ/lib/libluajit-5.1.a" \
	-DENABLE_CURL=1 -DCMAKE_BUILD_TYPE=Release >/dev/null
sudo -u "$SVC_USER" make -C "$SRC/build" -j"$(nproc)" >/dev/null
"$SRC/bin/luantiserver" --version | head -2

echo "== 4. Game and world"
# The service user needs to read the repo; give it its own copy so it never
# depends on someone's home directory permissions.
GAME="$BASE/game"
rsync -a --delete --exclude .git "$REPO_DIR/" "$GAME/"
chown -R "$SVC_USER:$SVC_USER" "$GAME"
ln -sfn "$GAME" "$SRC/games/orthoverse"

WORLD="$SRC/worlds/orthoverse"
if [[ ! -f "$WORLD/world.mt" ]]; then
	sudo -u "$SVC_USER" mkdir -p "$WORLD"
	sudo -u "$SVC_USER" tee "$WORLD/world.mt" >/dev/null <<EOF
gameid = orthoverse
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF
fi

CONF="$BASE/orthoverse.conf"
if [[ ! -f "$CONF" ]]; then
	sudo -u "$SVC_USER" tee "$CONF" >/dev/null <<EOF
# Orthoverse server settings (map settings come from the game's minetest.conf)
server_name = The Orthoverse
server_description = Every land is an Orthoverse token.
server_announce = false
port = $PORT
max_users = 50
enable_damage = true
creative_mode = false

# Mapgen threads: plenty of cores on node 0
num_emerge_threads = 16

# Bounded, pre-generated world: send what players can see, not more
max_block_send_distance = 10
max_simultaneous_block_sends_per_client = 40
active_block_range = 3

# Media will come from orthoverse.land once that is set up:
# remote_media = https://orthoverse.land/media/
EOF
fi
chown "$SVC_USER:$SVC_USER" "$CONF"

echo "== 5. systemd service (pinned to NUMA node 0, not started)"
cat > /etc/systemd/system/orthoverse.service <<EOF
[Unit]
Description=Orthoverse Luanti server
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
Group=$SVC_USER
WorkingDirectory=$SRC
ExecStart=$SRC/bin/luantiserver --config $CONF --world $WORLD --logfile $WORLD/debug.txt
Restart=on-failure
RestartSec=10
# NUMA node 0: CPUs 0-11 and their hyperthreads 24-35, memory from node 0 only
CPUAffinity=0-11 24-35
NUMAPolicy=bind
NUMAMask=0
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$BASE

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

echo
echo "Done. Next:"
echo "  sudo -u $SVC_USER $REPO_DIR/tools/proliant/pregen.sh   # generate the whole map once"
echo "  sudo systemctl enable --now orthoverse"
echo "Check UDP $PORT is free first:  sudo ss -ulpn | grep :$PORT"
