#!/usr/bin/env bash
# Throw away the generated map and generate it again with the current game.
# Accounts and player data are kept; anything built in the world is lost
# (the old map is kept in backups/ so it can be restored).
#   sudo ./tools/proliant/regen.sh
set -euo pipefail
BASE="${BASE:-/mnt/ethereum/orthoverse}"
SVC_USER="${SVC_USER:-ovserver}"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORLD="$BASE/luanti/worlds/orthoverse"
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
echo "This replaces the whole map. Anything built in the world will be gone."
read -r -p "Type 'regen' to continue: " ok
[[ "$ok" == "regen" ]] || { echo "Cancelled."; exit 1; }

rsync -a --delete --exclude .git "$REPO_DIR/" "$BASE/game/"
chown -R "$SVC_USER:$SVC_USER" "$BASE/game"
systemctl stop orthoverse
stamp="$(date +%Y%m%d-%H%M)"
if [[ -f "$WORLD/map.sqlite" ]]; then
	mv "$WORLD/map.sqlite" "$BASE/backups/map-$stamp.sqlite"
	echo "Old map moved to $BASE/backups/map-$stamp.sqlite"
fi
sudo -u "$SVC_USER" env BASE="$BASE" "$BASE/game/tools/proliant/pregen.sh"
systemctl start orthoverse
echo "Map regenerated and server started."
