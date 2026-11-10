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
cd "$(dirname "$0")" || exit 1

usage() {
	sed -n '2,/^cd /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
	exit 2
}

cmd=$1
[ -n "$cmd" ] || usage
case "$cmd" in
	list) ;;
	show|lock|unlock|recovery|delete) [ -n "$2" ] || usage ;;
	*) usage ;;
esac

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
