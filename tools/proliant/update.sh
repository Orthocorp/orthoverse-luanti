#!/usr/bin/env bash
# Copy this repo's game into the server after a git pull, then restart.
# Map changes only apply to land generated afterwards: use regen.sh for that.
#   cd ~/orthoverse-luanti && git pull && sudo ./tools/proliant/update.sh
set -euo pipefail
BASE="${BASE:-/mnt/ethereum/orthoverse}"
SVC_USER="${SVC_USER:-ovserver}"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
rsync -a --delete --exclude .git "$REPO_DIR/" "$BASE/game/"
chown -R "$SVC_USER:$SVC_USER" "$BASE/game"
systemctl restart orthoverse
echo "Game updated to $(git -C "$REPO_DIR" log -1 --format='%h %s') and server restarted."
