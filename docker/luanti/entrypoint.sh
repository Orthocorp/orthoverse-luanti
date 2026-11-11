#!/bin/sh
# Start the Orthoverse server in its container.
#
#   serve                  run the server (the default)
#   pregen [RADIUS] [X,Z]  generate the map (default: all of it), then exit;
#                          stop the running server first
#
# Settings come from /etc/orthoverse/orthoverse.conf (docker/luanti/orthoverse.conf
# in the repository); the world is the directory mounted at /world.
set -eu

CONF_SRC=/etc/orthoverse/orthoverse.conf
WORLD=/world
CONF=/tmp/orthoverse.conf

if [ ! -w "$WORLD" ]; then
	echo "The world at $WORLD is missing or not writable by user $(id -u)." >&2
	echo "Check OV_WORLD, OV_UID and OV_GID in .env." >&2
	exit 1
fi

# A new world: the same settings install.sh used
if [ ! -f "$WORLD/world.mt" ]; then
	cat > "$WORLD/world.mt" <<EOF
gameid = orthoverse
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF
fi

# The world's databases in WAL mode (once; it stays set in each file): the
# backup, the map and the auth service then read them while the game saves,
# without either waiting for the other. (In SQLite's default mode a long
# read, such as the nightly backup's copy of the map, holds the game's saves
# back, and after a while the game gives up and stops.)
for db in "$WORLD"/*.sqlite; do
	[ -f "$db" ] || continue
	mode=$(sqlite3 -cmd ".timeout 10000" "$db" "PRAGMA journal_mode = WAL;" 2>&1) || true
	[ "$mode" = wal ] || echo "Could not put $(basename "$db") in WAL mode ($mode); it stays as it was" >&2
done

cp "$CONF_SRC" "$CONF"
# In the container the server listens on the private Compose network, which
# only the web proxy can reach: publishing no port is what keeps it web only.
# IPv4 on all the container's interfaces (Docker's networks have no IPv6, and
# Luanti would otherwise try IPv6 first and fail).
sed -i '/^bind_address[ =]/d' "$CONF"
echo "bind_address = 0.0.0.0" >> "$CONF"

# The admin: the player with this name has every privilege (fly, noclip, fast,
# teleport, give, ban, granting privileges to others, ...)
sed -i '/^name[ =]/d' "$CONF"
if [ -n "${OV_ADMIN:-}" ]; then
	case "$OV_ADMIN" in
		*[!A-Za-z0-9_-]*)
			echo "OV_ADMIN must be a player name (letters, digits, - and _)" >&2
			exit 1 ;;
	esac
	echo "name = $OV_ADMIN" >> "$CONF"
	echo "Admin: $OV_ADMIN"
fi

mode="${1:-serve}"
case "$mode" in
	serve) ;;
	pregen)
		cat >> "$CONF" <<EOF
orthoverse_pregen_radius = ${2:-58}
orthoverse_pregen_centre = ${3:-0,0}
orthoverse_pregen_exit = true
orthoverse_render_map = true
EOF
		echo "Pre-generating radius ${2:-58} around land ${3:-0,0}"
		;;
	*)
		exec "$@"
		;;
esac

# Pin to one NUMA node (the ProLiant: node 0), CPUs and memory, as the old
# systemd service did. Needs cap_add SYS_NICE for the memory part.
set --
if [ -n "${OV_NUMA_NODE:-}" ]; then
	if numactl --cpunodebind="$OV_NUMA_NODE" --membind="$OV_NUMA_NODE" true 2>/dev/null; then
		set -- numactl --cpunodebind="$OV_NUMA_NODE" --membind="$OV_NUMA_NODE"
		echo "Pinned to NUMA node $OV_NUMA_NODE"
	else
		echo "Could not pin to NUMA node $OV_NUMA_NODE; running unpinned" >&2
	fi
fi

exec "$@" /opt/luanti/bin/luantiserver --config "$CONF" --world "$WORLD" \
	--logfile "$WORLD/debug.txt"
