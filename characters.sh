#!/bin/sh
# Managing the Orthoverse's characters, on the server, from the repository
# folder. It asks the running auth service (nothing here is reachable from
# the internet).
#
#   ./characters.sh list [text]          every character (or those whose name or
#                                        wallet contains the text), and the guests
#   ./characters.sh show <name>          one character in full
#   ./characters.sh lock <name> [reason] keep them out: signed out on the website,
#                                        put out of the game, until unlocked
#   ./characters.sh unlock <name>
#   ./characters.sh recovery <name>      a new recovery code, for a player who has
#                                        lost both password and code (check first
#                                        that it really is them)
#   ./characters.sh delete <name>        delete the character for good (asks first):
#                                        the website forgets it and the game removes
#                                        its account, what it carries and where it is
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
	show|lock|unlock|recovery|delete|who|ban|unban) [ -n "$2" ] || usage ;;
	*) usage ;;
esac

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
if r.get("error"):
    print(r["error"]); sys.exit(1)
if "characters" in r:
    rows = r["characters"]
    def short(a): return a[:6] + "..." + a[-4:] if a else "-"
    table = [("Name", "Wallet", "Password", "Since", "Last played", "Locked")]
    for c in rows:
        table.append((c["name"], short(c["wallet"]), "yes" if c["password"] else "no",
            (c["since"] or "-")[:10], c["lastPlayed"] or "never",
            ("yes: " + c["locked"]) if isinstance(c["locked"], str) else ("yes" if c["locked"] else "")))
    w = [max(len(t[i]) for t in table) for i in range(6)]
    for t in table:
        print("  ".join(t[i].ljust(w[i]) for i in range(6)).rstrip())
    print("\n%d character%s; %d guest account%s in the game" % (len(rows), "" if len(rows) == 1 else "s",
        r["guests"], "" if r["guests"] == 1 else "s"))
elif "done" in r:
    print(r["done"])
else:
    labels = [("name", "Name"), ("wallet", "Wallet"), ("password", "Password"), ("since", "Made"),
        ("lastPlayed", "Last played"), ("lastEntry", "Last entry from the site"), ("gameAccount", "Game account"),
        ("locked", "Locked"), ("skin", "Own skin"), ("admin", "The admin"), ("lands", "Lands held"), ("visit", "Arriving at")]
    for k, label in labels:
        v = r.get(k)
        if isinstance(v, bool): v = "yes" if v else "no"
        elif isinstance(v, list): v = ", ".join(v) if v else "none"
        elif isinstance(v, dict): v = json.dumps(v)
        elif v is None: v = "-"
        print("%-26s %s" % (label + ":", v))
'
