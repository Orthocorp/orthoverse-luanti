#!/usr/bin/env bash
# Set up the Orthoverse website on the ProLiant: landing page, world map, the
# browser client's page and the web proxy that connects browser players to the
# Luanti server. Safe to re-run; re-running also updates the site and proxy.
#
#   sudo ./tools/proliant/install-web.sh
#
# What it does:
#   1. installs packages (nginx is already there; build tools for the client)
#   2. puts Node 24 in /mnt/ethereum/orthoverse/node (system Node is untouched)
#   3. copies the site and the proxy to /mnt/ethereum/orthoverse/web
#   4. makes a Python venv and renders the map tiles from the world
#   5. installs and starts the orthoverse-webproxy service
#   6. adds an nginx site on 127.0.0.1:8484 (localhost only) and reloads nginx
#   7. makes the Luanti server listen on 127.0.0.1 only, so the web is the only
#      way in (WEB_ONLY=0 skips this and leaves the server open on the network)
#
# It does not build the browser client (run web/client/build.sh after this),
# and it does not touch Cloudflare: see web/README.md for the tunnel step.
set -euo pipefail

BASE="${BASE:-/mnt/ethereum/orthoverse}"
SVC_USER="${SVC_USER:-ovserver}"
WEB_PORT="${WEB_PORT:-8484}"
PROXY_PORT="${PROXY_PORT:-8737}"
NODE_VERSION="${NODE_VERSION:-v24.22.0}"
WEB_ONLY="${WEB_ONLY:-1}"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WEB="$BASE/web"

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
id "$SVC_USER" >/dev/null 2>&1 || { echo "User $SVC_USER missing: run install.sh first." >&2; exit 1; }
as_svc() { sudo -u "$SVC_USER" "$@"; }

for p in "$WEB_PORT" "$PROXY_PORT"; do
	if ss -ltn "sport = :$p" | grep -q LISTEN && ! systemctl is-active -q orthoverse-webproxy; then
		if [[ $p == "$PROXY_PORT" ]] || ! grep -qs "127.0.0.1:$WEB_PORT" /etc/nginx/sites-enabled/orthoverse-web.conf; then
			echo "Port $p is already in use; choose another with WEB_PORT= or PROXY_PORT=." >&2
			exit 1
		fi
	fi
done

echo "== 1. Packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx rsync wget xz-utils \
	python3-venv build-essential cmake tclsh python3 git zip zstd gettext >/dev/null

echo "== 2. Node $NODE_VERSION in $BASE/node"
if [[ "$("$BASE/node/bin/node" --version 2>/dev/null || true)" != "$NODE_VERSION" ]]; then
	tmp=$(mktemp -d)
	tarball="node-$NODE_VERSION-linux-x64.tar.xz"
	wget -q "https://nodejs.org/dist/$NODE_VERSION/$tarball" -O "$tmp/$tarball"
	wget -q "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -O "$tmp/SHASUMS256.txt"
	(cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c -)
	tar xJf "$tmp/$tarball" -C "$tmp"
	rm -rf "$BASE/node"
	mv "$tmp/node-$NODE_VERSION-linux-x64" "$BASE/node"
	rm -rf "$tmp"
	chown -R "$SVC_USER:$SVC_USER" "$BASE/node"
fi
"$BASE/node/bin/node" --version

echo "== 3. Game copy, site and proxy in $WEB"
# The map tools run from the server's copy of the repo, so refresh it (the
# running server is unaffected until it restarts)
rsync -a --delete --exclude .git "$REPO_DIR/" "$BASE/game/"
chown -R "$SVC_USER:$SVC_USER" "$BASE/game"
mkdir -p "$WEB/site" "$WEB/proxy" "$WEB/play"
# The site; generated map files (tiles, lands.json) are kept
rsync -a --delete --exclude map/tiles --exclude map/lands.json \
	"$REPO_DIR/web/site/" "$WEB/site/"
rsync -a --delete --exclude node_modules "$REPO_DIR/web/proxy/" "$WEB/proxy/"
chown -R "$SVC_USER:$SVC_USER" "$WEB"
(cd "$WEB/proxy" && as_svc env PATH="$BASE/node/bin:$PATH" npm ci --omit=dev --no-audit --no-fund --loglevel=error)
# nginx (www-data) reads the site: directories must be traversable
chmod o+rx "$BASE" "$WEB" 2>/dev/null || true
if ! sudo -u www-data test -r "$WEB/site/index.html"; then
	echo "nginx cannot read $WEB/site: check permissions on $(dirname "$BASE")" >&2
	exit 1
fi

echo "== 4. Map tiles"
if [[ ! -x "$BASE/venv/bin/python" ]]; then
	as_svc python3 -m venv "$BASE/venv"
fi
as_svc "$BASE/venv/bin/pip" install -q --upgrade pip
as_svc "$BASE/venv/bin/pip" install -q numpy zstandard pillow
cp "$REPO_DIR/tools/proliant/make-map.sh" "$BASE/make-map.sh"
chown "$SVC_USER:$SVC_USER" "$BASE/make-map.sh"
chmod +x "$BASE/make-map.sh"
as_svc env BASE="$BASE" "$BASE/make-map.sh"

echo "== 5. Web proxy service"
sed -e "s|@BASE@|$BASE|g" -e "s|@SVC_USER@|$SVC_USER|g" -e "s|@PROXY_PORT@|$PROXY_PORT|g" \
	"$REPO_DIR/web/systemd/orthoverse-webproxy.service" > /etc/systemd/system/orthoverse-webproxy.service
systemctl daemon-reload
systemctl enable -q orthoverse-webproxy
systemctl restart orthoverse-webproxy

echo "== 6. nginx site on 127.0.0.1:$WEB_PORT"
sed -e "s|@BASE@|$BASE|g" -e "s|@PORT@|$WEB_PORT|g" -e "s|@PROXY_PORT@|$PROXY_PORT|g" \
	"$REPO_DIR/web/nginx/orthoverse-web.conf" > /etc/nginx/sites-available/orthoverse-web.conf
ln -sfn /etc/nginx/sites-available/orthoverse-web.conf /etc/nginx/sites-enabled/orthoverse-web.conf
nginx -t
systemctl reload nginx

echo "== 7. Game server reachable only through the web"
CONF="$BASE/orthoverse.conf"
if [[ "$WEB_ONLY" == 1 ]]; then
	if grep -q '^bind_address = 127.0.0.1$' "$CONF"; then
		echo "Already web only."
	else
		sed -i '/^bind_address *=/d' "$CONF"
		echo 'bind_address = 127.0.0.1' >> "$CONF"
		echo "Set bind_address = 127.0.0.1; restarting the game server (players are disconnected)."
		systemctl restart orthoverse
	fi
	sleep 3
	ss -ulnH 'sport = :30000' | awk '{print "Luanti listens on " $4}'
else
	echo "WEB_ONLY=0: leaving $CONF as it is."
fi

echo
echo "Done. Check it locally:  curl -sI http://127.0.0.1:$WEB_PORT/ | head -1"
echo "Next: build the browser client (web/client/build.sh), then point orthoverse.land at"
echo "http://127.0.0.1:$WEB_PORT in the Cloudflare tunnel (see web/README.md)."
