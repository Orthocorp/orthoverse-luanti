#!/usr/bin/env bash
# Generate the whole Orthoverse surface once, render an overview, then exit.
# Run as the service user with the service stopped:
#   sudo systemctl stop orthoverse
#   sudo -u ovserver ./pregen.sh            # whole map (radius 58 lands)
#   sudo -u ovserver ./pregen.sh 3 0,0      # quick test: 7 x 7 lands round Orthohenge
set -euo pipefail
BASE="${BASE:-/mnt/ethereum/orthoverse}"
RADIUS="${1:-58}"
CENTRE="${2:-0,0}"
SRC="$BASE/luanti"
WORLD="$SRC/worlds/orthoverse"
TMPCONF="$(mktemp)"
cat "$BASE/orthoverse.conf" > "$TMPCONF"
cat >> "$TMPCONF" <<EOF
port = 30099
orthoverse_pregen_radius = $RADIUS
orthoverse_pregen_centre = $CENTRE
orthoverse_pregen_exit = true
orthoverse_render_map = true
EOF
echo "Pre-generating radius $RADIUS around land $CENTRE (log: $WORLD/debug.txt)"
# Pin to NUMA node 0 on the ProLiant (skipped on machines with fewer CPUs)
PIN=()
if [[ $(nproc) -ge 36 ]]; then PIN=(taskset -c 0-11,24-35); fi
"${PIN[@]}" "$SRC/bin/luantiserver" --config "$TMPCONF" --world "$WORLD" \
	--logfile "$WORLD/debug.txt"
rm -f "$TMPCONF"
grep "orthoverse_admin" "$WORLD/debug.txt" | tail -3
if [[ $RADIUS -le 10 ]]; then
	echo "Overview image: $WORLD/orthomap.ppm"
else
	echo "For an overview of the whole map: tools/render_map.py $WORLD/map.sqlite orthomap.png"
fi
