#!/bin/sh
# How the Orthoverse is doing: the auth service's status (players, lands, when
# land ownership was last read and any error, the OpenSea refresh). Run it on
# the server, from the repository folder:
#
#   ./status.sh
#
# The page answers only here, on the server: from the internet (through
# Cloudflare) it is not there.
cd "$(dirname "$0")" || exit 1
port=8485
if [ -f .env ]; then
	p=$(sed -n 's/^OV_WEB_PORT=\([0-9][0-9]*\).*/\1/p' .env | tail -n 1)
	[ -n "$p" ] && port=$p
fi
out=$(curl -fsS --max-time 10 "http://127.0.0.1:$port/auth/status") || {
	echo "No answer from http://127.0.0.1:$port/auth/status: is it running? (docker compose ps)" >&2
	exit 1
}
if command -v python3 >/dev/null 2>&1; then
	printf '%s\n' "$out" | python3 -m json.tool
else
	printf '%s\n' "$out"
fi
