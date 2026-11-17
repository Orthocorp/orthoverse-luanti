#!/bin/sh
# Managing the Orthoverse's characters, on the server, from the repository
# folder. It asks the running auth service (nothing here is reachable from
# the internet).
#
#   ./characters.sh list [column] [text] every character (or those whose name or
#                                        wallet contains the text), and the guests;
#                                        sorted by a column if one is named: name,
#                                        wallet, password, since or last (newest
#                                        first), time (most first), locked
#   ./characters.sh show <name>          one character in full, with the time they
#                                        have spent in the world (counted from patch
#                                        1158), and in this visit if there now; their
#                                        rank, experience, stats and the adventures
#                                        they have finished
#   ./characters.sh lock <name> [reason] keep them out: signed out on the website,
#                                        put out of the game, until unlocked
#   ./characters.sh unlock <name>
#   ./characters.sh recovery <name>      a new recovery code, for a player who has
#                                        lost both password and code (check first
#                                        that it really is them)
#   ./characters.sh delete <name>        delete the character for good (asks first):
#                                        the website forgets it and the game removes
#                                        its account, what it carries and where it is
#   ./characters.sh where <name>         the land they are on (or logged out on), and
#                                        the place, ready for /teleport: from the game's
#                                        last save, so a few moments behind for someone
#                                        playing now
#
# Keeping someone out by their address (a guest, who has no character to
# lock): everyone reaches the game through the web proxy, so the game sees
# one address for all and its own /ban would shut everyone out.
#
#   ./characters.sh who <name>           the addresses a player (or guest) came
#                                        from in the last two days, from the proxy's log
#   ./characters.sh ban <address> [why]  keep an address out: put out of the game at
#                                        once, and refused until unbanned
#   ./characters.sh unban <address>
#   ./characters.sh bans                 the addresses kept out
cd "$(dirname "$0")" || exit 1

usage() {
	sed -n '2,/^cd /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
	exit 2
}

cmd=$1
[ -n "$cmd" ] || usage
case "$cmd" in
	list|bans) ;;
	show|lock|unlock|recovery|delete|who|where|ban|unban) [ -n "$2" ] || usage ;;
	*) usage ;;
esac

# Where a character is: the game's player database (positions in tenths of a
# block), and the land there from the lands file (96 blocks a side)
if [ "$cmd" = where ]; then
	case "$2" in *[!A-Za-z0-9_-]*) echo "That is not a player name." >&2; exit 2 ;; esac
	at=$(docker compose exec -T luanti sqlite3 -readonly -separator ' ' /world/players.sqlite \
		"SELECT name, posX/10.0, posY/10.0, posZ/10.0 FROM player WHERE lower(name) = lower('$2')" 2>&1)
	status=$?
	if [ $status -ne 0 ]; then echo "Could not read the game's players (is it running? docker compose ps): $at" >&2; exit 1; fi
	if [ -z "$at" ]; then echo "The game has no character called $2."; exit 1; fi
	printf '%s\n' "$at" | python3 -c '
import json, math, sys
name, x, y, z = sys.stdin.read().split()
x, y, z = float(x), float(y), float(z)
key = "%d:%d" % (math.floor((x + 48) / 96), -math.floor((z + 48) / 96))
d = json.load(open("mods/orthoverse_lands/data/lands.json"))
land = d["lands"].get(key) or d["henges"].get(key)
print("%s is on %s (%s), at %d,%d,%d" % (name, land["name"] if land else "the open sea or the rim", key,
	math.floor(x), math.floor(y + 0.5), math.floor(z)))'
	exit $?
fi

# The proxy's list of addresses kept out: OV_DATA/proxy/blocked.txt
if [ "$cmd" = who ]; then
	case "$2" in *[!A-Za-z0-9_-]*) echo "That is not a player name." >&2; exit 2 ;; esac
	found=$(docker compose logs --no-log-prefix --since 48h proxy 2>/dev/null | grep -i " is $2\$")
	if [ -z "$found" ]; then echo "$2 has not come through the proxy in the last two days."; exit 1; fi
	printf '%s\n' "$found" | awk '{ print substr($1, 1, 16), $3 }' | sed 's/T/ /'
	exit 0
fi
case "$cmd" in
	ban|unban|bans)
		data=$(sed -n 's/^OV_DATA=//p' .env 2>/dev/null | tail -n 1)
		if [ -z "$data" ]; then echo "OV_DATA is not set in .env" >&2; exit 1; fi
		mkdir -p "$data/proxy" 2>/dev/null
		file="$data/proxy/blocked.txt"
		[ -f "$file" ] || { : > "$file"; } 2>/dev/null
		if [ ! -w "$file" ]; then
			echo "Cannot write $file (made by Docker?): sudo chown -R $(id -u):$(id -g) $data/proxy" >&2
			exit 1
		fi
		;;
esac
if [ "$cmd" = bans ]; then
	if grep -q '[^[:space:]]' "$file"; then cat "$file"; else echo "No addresses are kept out."; fi
	exit 0
fi
if [ "$cmd" = ban ] || [ "$cmd" = unban ]; then
	ip=$2
	if ! printf '%s' "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*$'; then
		echo "That is not an address: $ip" >&2; exit 2
	fi
	rest=$(awk -v ip="$ip" 'tolower($1) != tolower(ip)' "$file")
	if [ "$cmd" = ban ]; then
		shift 2
		why=$(printf '%s' "$*" | tr -d '\n')
		{ [ -n "$rest" ] && printf '%s\n' "$rest"; printf '%s  # %s %s\n' "$ip" "$(date -u +%Y-%m-%d)" "$why"; } > "$file.new"
		mv "$file.new" "$file"
		echo "$ip is kept out: put out of the game within 10 seconds, and refused until unbanned."
	else
		if [ "$rest" = "$(cat "$file")" ]; then echo "$ip was not kept out."; exit 0; fi
		{ [ -n "$rest" ] && printf '%s\n' "$rest"; } > "$file.new"
		mv "$file.new" "$file"
		echo "$ip may come in again."
	fi
	exit 0
fi

if [ "$cmd" = delete ]; then
	printf 'Delete %s for good? Type the name again to go ahead: ' "$2"
	read -r again
	if [ "$again" != "$2" ]; then echo "Not deleted."; exit 1; fi
fi

# list <column>: sorted by that column (the rest, if any, is the text to look for)
SORT=
if [ "$cmd" = list ]; then
	case "$(printf '%s' "$2" | tr 'A-Z' 'a-z')" in
		name|wallet|password|since|last|played|lastplayed|last_played|time|locked)
			SORT=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
			shift 2
			set -- list "$@"
			;;
	esac
fi
export SORT

out=$(docker compose exec -T auth node admin.js "$@")
status=$?
if [ -z "$out" ]; then
	echo "No answer from the auth service: is it running? (docker compose ps)" >&2
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	printf '%s\n' "$out"
	exit $status
fi

printf '%s\n' "$out" | python3 -c '
import json, sys
r = json.load(sys.stdin)
# Seconds as hours, minutes and seconds: 3h 05m 09s
def hms(n):
    if n is None: return "-"
    n = int(n); h, m, s = n // 3600, n // 60 % 60, n % 60
    return "%dh %02dm %02ds" % (h, m, s) if h else "%dm %02ds" % (m, s) if m else "%ds" % s
if r.get("error"):
    print(r["error"]); sys.exit(1)
if "characters" in r:
    rows = r["characters"]
    # Sorted by a column (SORT): dates newest first, never at the end; yes first
    import os
    by = os.environ.get("SORT", "")
    if by == "name": rows.sort(key=lambda c: c["name"].lower())
    elif by == "wallet": rows.sort(key=lambda c: (not c["wallet"], (c["wallet"] or "").lower()))
    elif by == "password": rows.sort(key=lambda c: (not c["password"], c["name"].lower()))
    elif by == "since": rows.sort(key=lambda c: c["since"] or "", reverse=True)
    elif by in ("last", "played", "lastplayed", "last_played"):
        rows.sort(key=lambda c: c["lastPlayed"] or "", reverse=True)
    elif by == "time": rows.sort(key=lambda c: c.get("played") or 0, reverse=True)
    elif by == "locked": rows.sort(key=lambda c: (not c["locked"], c["name"].lower()))
    def short(a): return a[:6] + "..." + a[-4:] if a else "-"
    table = [("Name", "Wallet", "Password", "Since", "Last played", "In the world", "Locked")]
    for c in rows:
        t = hms(c.get("played"))
        if c.get("online") is not None: t += " (here now)"
        table.append((c["name"], short(c["wallet"]), "yes" if c["password"] else "no",
            (c["since"] or "-")[:10], c["lastPlayed"] or "never", t,
            ("yes: " + c["locked"]) if isinstance(c["locked"], str) else ("yes" if c["locked"] else "")))
    w = [max(len(t[i]) for t in table) for i in range(7)]
    for t in table:
        print("  ".join(t[i].ljust(w[i]) for i in range(7)).rstrip())
    print("\n%d character%s; %d guest account%s in the game" % (len(rows), "" if len(rows) == 1 else "s",
        r["guests"], "" if r["guests"] == 1 else "s"))
elif "done" in r:
    print(r["done"])
else:
    labels = [("name", "Name"), ("wallet", "Wallet"), ("password", "Password"), ("since", "Made"),
        ("lastPlayed", "Last played"), ("played", "Time in the world"), ("online", "In the world now"),
        ("lastEntry", "Last entry from the site"), ("gameAccount", "Game account"),
        ("locked", "Locked"), ("skin", "Own skin"), ("admin", "The admin"), ("lands", "Lands held"), ("visit", "Arriving at")]
    for k, label in labels:
        v = r.get(k)
        if k == "played": v = hms(v)
        elif k == "online": v = ("yes, for " + hms(v)) if v is not None else "no"
        elif isinstance(v, bool): v = "yes" if v else "no"
        elif isinstance(v, list): v = ", ".join(v) if v else "none"
        elif isinstance(v, dict): v = json.dumps(v)
        elif v is None: v = "-"
        print("%-26s %s" % (label + ":", v))
    sh = r.get("sheet")
    if not sh:
        print("%-26s %s" % ("Character sheet:", "none yet (not in the world since sheets began)"))
    else:
        nxt = (" (rank %d at %d)" % (sh["rank"] + 1, sh["next"])) if sh.get("next") else " (the highest rank)"
        rows = [("Rank", str(sh["rank"])), ("Experience", "%d%s" % (sh["xp"], nxt)),
            ("Stamina", "%d / %d" % (sh["hp"], sh["hp_max"])),
            ("Insight, Agility, Prowess", "%d, %d, %d" % (sh["insight"], sh["agility"], sh["prowess"])),
            ("Prestige", str(sh["prestige"])), ("Sheet as of", (sh.get("at") or "-").replace("T", " ")[:16])]
        for label, v in rows:
            print("%-26s %s" % (label + ":", v))
        done = sh.get("done")
        if done is None:
            print("%-26s %s" % ("Adventures finished:", "not on the sheet yet (comes the next time they are in the world)"))
        else:
            print("%-26s %s" % ("Adventures finished:", "%d" % len(done) if done else "none"))
            for d in done:
                print("  " + d)
'
