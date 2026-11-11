# Security review, November 2026

A sweep of everything built so far: the game mods, the auth service, the web
proxy, the website, nginx and the Docker setup. What was found, what was
fixed (patch 1038), and what is left.

## How the pieces are exposed

- Only nginx is published, on 127.0.0.1, reached through the Cloudflare
  tunnel. Nothing listens on a public address.
- The Luanti server sits on an internal Docker network with no way in or out
  except the web proxy, which relays the game's datagrams to that one server
  and nothing else (no TCP, no other addresses, names answered for the
  Orthoverse only).
- The auth service holds the only secret (OV_AUTH_SECRET, in .env, which git
  ignores). The game reads its registry read-only; the auth service reads the
  game's accounts read-only.
- Containers run as the service user, most of them read-only.

## Fixed

### Critical: anyone could take a new character

Luanti makes an account the first time a client joins under a name, with
whatever password that client sends. The website hands each character a
password, but the game account did not exist until the player first joined.
Anyone who learned a new name (the lands page, the map, chat) and joined first
owned the character for good, including the admin's name before the admin's
first join (the admin mod gives that name every privilege).

Now the auth service stores, for each character, the game account's password
record (an SRP verifier, exactly as Luanti stores it; web/auth/srp.js), and
the game makes the account itself, before the engine looks the name up
(orthoverse_wallets, on_prejoinplayer). A client with the wrong password is
refused like any wrong password. A character without a record yet is told to
try again in a minute. Characters made before the change get a record when the
auth service starts.

Tested with the native client against the real server: the right password
joins, a wrong one on the very first join is refused and does not make the
account.

(Since patch 1062 the game sets each character's account to the website's
password as it joins, so a character taken before the fix is given back the
next time its player enters from the website; the check-accounts tool that
listed them is gone.)

### High: loot chests could be emptied twice

A player's share opens as a private inventory. Closing it forgot which share
was open but left the items in the inventory, and taking was still allowed,
so a modified client could take everything, close, reopen and take it all
again. Taking now needs the share to be open, and closing (or leaving) empties
the private inventory.

### Medium: a spawner could flood the server

A spawner's "test" button brings its monsters every click, with no limit.
Anyone allowed to set a spawner (on their own land) could bring thousands of
entities and slow or crash the server. Now no more than 30 monsters near any
spawner; the button says so when there are enough.

### Medium: no browser security headers

Every response now carries nosniff, X-Frame-Options DENY, a referrer policy,
a permissions policy and HSTS, and the nginx version is hidden. Site pages get
a Content-Security-Policy: scripts only from the site and Cloudflare
Turnstile, fonts from Google, nothing loaded or sent to any other site, no
plugins, no framing, forms post only to the site. Checked in a browser: no
page breaks. The browser game (/play/) keeps its own headers without the
policy, because its engine builds code at run time.

### Lower

- **Dependencies.** ws 8.18.3 to 8.21.3 (the proxy), ethers 6.15.0 to 6.17.0
  (the auth service). `npm audit`: no known vulnerabilities in either.
- **Map tooltip.** A land's name was shown as HTML on the map; a holder could
  name a land with markup. Now shown as text. (Every other page already wrote
  text, not HTML.)
- **Registry lookups.** A name like `__proto__` looked up the object's
  prototype instead of a character. Harmless here, but lookups now check the
  name is really in the registry.
- **Token pictures.** Any token id's classic picture can be asked for, and
  drawing one costs time. Drawings not already cached are now rate-limited
  per address (60 a minute).
- **The proxy.** Connections that have not yet bound to the game are limited
  to 20 per address and 15 seconds, so nobody can hold open thousands of idle
  sockets. (Bound connections were already limited to 6 per address, 100 in
  all.)
- **/adventure place** checks the name is a plain name before building a file
  path from it (admin only, so not reachable by players).

## Checked, nothing to fix

- Sessions are signed with the secret and compared in constant time; cookies
  are HttpOnly, SameSite=Strict, Secure over https, limited to /auth. A
  password session ends when the password changes.
- Passwords and recovery codes are stored as scrypt hashes only. Logins are
  rate-limited per address and per name (15 minutes after repeated wrong
  passwords).
- Request bodies: JSON only, 8 KB at most (nginx: 16 KB).
- Wallet sign-in: the service writes the message to sign, keeps it, accepts
  a signature of exactly that message once, and only for a few minutes.
- Form handlers and chat commands in the mods check permission on the server
  (protection, admin privileges), not in the client.
- Backups and restore are operator-only; no web route touches them.
- No secrets in the repository or its history.

## Left as they are (known risks)

- **A modified game client can cheat** within what the server allows: aim, see
  through walls, record a faster adventure time. Luanti's server checks
  movement and digging roughly; records and rank should be treated as for fun.
- **Names can be checked.** /auth/exists says whether a name is taken (it has
  to, to make characters). Rate-limited.
- **A name can be locked out for 15 minutes** by someone typing wrong
  passwords for it on the website. The recovery code still works. The game's
  own login is separate and unaffected.
- **Wallet sessions cannot be ended early** except by signing out on that
  browser; they last 30 days. Changing OV_AUTH_SECRET ends every session (it
  signs everyone out).
- **Guests** (Guest-xxxxxx) are made by whoever joins first under the name,
  as before. They hold nothing worth taking.
- **The robot check** is off unless OV_TURNSTILE_SECRET is set. Set it in
  production.
- **Base images** (node, nginx, Ubuntu) are pinned; rebuild them now and then
  for security updates (`docker compose build --pull`).
- **Inline scripts.** Each page has an inline script, so the policy allows
  them; it limits what injected script could reach, but does not stop it
  running. Moving the scripts into files would allow a stricter policy.

## Second sweep, 10 November 2026

Everything since the first sweep (adventures, kits, the three new ready-made
adventures, the ship's and props' blocks, robots, the map's land list), and
the whole code base again for the classic holes: code run from input
(`eval`, `new Function`, `vm`, `child_process`, Lua `load`/`loadstring`/
`dofile` on anything not ours, `os.execute`, `io.popen`), injection (SQL,
shell, HTML, formspec), file paths from input, type confusion in request
bodies, prototype pollution, and old dependencies.

### Found nothing of the kind that hacked the old server

- No code anywhere runs input as code. The web services have no `eval`,
  `new Function`, `vm` or shell calls (the tests start the service, nothing
  else spawns processes). The mods have no `load`, `loadstring`,
  `os.execute` or `io.popen`; `dofile` only loads our own files. The one
  `exec` in Python compiles Emscripten's own port files at build time.
- SQL: every statement is fixed text with `?` parameters.
- Request bodies: every field is turned into a string or a number, and
  checked (lengths, a name pattern, a finite number within the world)
  before use; a body of `null`, a number or an array is refused, not
  crashed on.
- Formspecs: every text a player chose (adventure names and lines, records)
  is escaped; positions sent back from a form are checked (the node is
  what it should be, and the player may change it).
- Web pages write player text as text (`textContent`, `append`), never as
  HTML.
- File paths: only fixed folders plus names checked against a pattern or
  made from numbers.

### Fixed

- **Dependencies and base images.** nginx 1.27.5 to 1.30.6 (five CVEs this
  October; the alias and SSL ones fall in our version range, though our
  configuration avoids their conditions); Node 24.22.0 to 24.22.1 (an
  October security release: HTTP, DNS, TLS fixes); Python 3.12.7 to
  3.12.16; Pillow 11.0.0 to 13.0.0 (out-of-bounds writes in PSD and DDS
  decoding, and an EPS code-execution flaw). `npm audit`: nothing in
  either service. Luanti 5.18.0 is past every 2026 advisory (the sandbox
  escapes were fixed in 5.15.2).
- **Containers.** Every service now runs with `no-new-privileges` and no
  kernel capabilities but those it needs (the game server SYS_NICE for
  its memory binding; nginx the five it needs to start as root and drop
  to its own user). Tested: nginx serves with only those.
- **Things thrown out of a run.** Inside an adventure a dropped item now
  falls at the player's feet: before, a player could throw gold (or kit)
  over the Mill's yard wall to a friend outside without finishing.
- **Defence in depth.** Saved inventories are read with Luanti's safe
  deserialize (no functions); the auth service looks routes up as its own
  keys only.

### Left as they are

- The browser game's engine (luanti-wasm, pinned) runs in each player's
  browser, not on the server.
- As before: a modified client can cheat within what the server allows.

## Arriving at adventures (patches 1056 to 1058)

Players can now be sent to an adventure's entrance, by `/adventure go` or the
Adventures page's Play button. Where they arrive is always the open
adventure's own arrival point, from the game's data: the browser names only
a land key, which the auth service checks against the open adventures, and
the game checks again. The choice is tied to the signed-in character (the
session, not the request, gives the name), used once, and kept 10 minutes.
Arriving at any spot from the map still needs a level 7 land.

The arrival point is set by the adventure's builder, so it could have been a
trap (set in the air, or a pit or lava put under it later) for strangers
sent from the website. It is now checked for solid ground, room to stand and
nothing that burns nearby when it is set, when the adventure opens, and
before anyone is sent; an unsafe one sends nobody.

## Game passwords made fresh for each entry (patch 1062)

The game server checks a name and password of its own. Until now each
character's game password was derived from the server's secret and the name,
the same for good, and handed to the signed-in player's page. Changing or
recovering the website password did not change it, so anyone who had ever
learned it (from a shared computer, or the browser's developer tools while
signed in) kept the character in the game; and the game's own "Change
password" let them lock its owner out, with no way back but the admin's
/setpassword.

Now the auth service makes a fresh random password each time a signed-in
player presses Enter (POST /auth/play) and keeps only its record, with the
time. As the player joins, the game sets the account to that record and lets
it in once, within ten minutes; then it is used up. A password that leaks, or
one changed in the game's menu, is no use afterwards. /auth/me no longer
gives any password.

The admin's name (OV_ADMIN) gets every privilege in the game, so nobody else
may take it on the website. To make it there the first time, run the auth
service once with OV_ADMIN_OPEN=1.

## Third sweep, 11 November 2026

Ahead of more visitors after the Substack article. This covered everything
added since the second sweep (3D Armor, skins, guests, the reveal and level
routes, OpenSea, the status page, the admin socket, the proxy's logging and the
engine patches). It also asked a new question of the whole service: what can
one person, or a script with many addresses, do to it?

### Fixed (patches 1102 to 1104)

- **Free diamond armour from creative mode (high, for the game).** 3D Armor
  drops what a player wears when they die, and creative mode does not stop
  /killme. Armour from the Creative tab then lay on the ground for anyone to
  pick up. This was tested and confirmed. A creative player's armour is now
  removed before 3D Armor sees it. Ordinary deaths are unchanged (armour goes
  into bones).
- **Unlimited wallet characters (medium).** Making a wallet costs nothing, so
  a script could make any number of characters, one fresh wallet each,
  without the per-address limit or Turnstile. Each sign-in also asked the
  chain about every land, in a queue with no limit. Now:
  - wallet characters count against the three a day per address;
  - at most 60 new characters of either kind are made an hour, from all
    addresses together (`OV_NEW_PER_HOUR`);
  - a new wallet's lands are looked up only when lookups are not busy.
- **Using up the RPC endpoint (medium).** Anyone could make the auth service
  ask the chain things: a land's level, whether a token is revealed, a
  fresh wallet's lands. From many addresses this could use up the public
  endpoint's allowance, and the lookups the game needs would then fail. These
  are now limited to 60 a minute from all addresses together
  (`OV_PUBLIC_RPC_PER_MIN`). Beyond that, visitors are asked to try again in
  a minute.
- **No way to keep a troublemaker out (medium).** Everyone reaches the game
  through the web proxy, so the game sees one address for all players. A
  guest has no character to lock, and the engine's /ban would have shut out
  every player. Now:
  - the proxy logs the name each game client gives, next to its real
    address;
  - it keeps out the addresses listed in `OV_DATA/proxy/blocked.txt`, and
    closes connections from a newly listed one within ten seconds;
  - `./characters.sh who / ban / unban / bans` manage the list;
  - /ban and /unban in the game now say what to do instead.
- **Floods through the proxy (low).** One browser can send at most 1000
  datagrams a second to the game (`OV_DATAGRAMS_PER_SECOND`); the rest are
  dropped at the proxy. This was tested with a flood of 5000.
- **Small leaks of memory (low).** Old entries in the per-address and
  per-name limits were never cleared. They are now.

### Checked, nothing to fix

- No code runs input as code. In the web services there is no `eval`,
  `new Function`, `vm` or process spawning. In our mods there is no `load`,
  `loadstring`, `os.execute` or `io.popen`. WorldEdit's own loaders only read
  our ready-made adventure files, and its Lua commands need `server`, which
  only the admin has.
- Skins: the website paints each picture itself from its own parts, and a
  design is checked field by field. The game reads only `<name>.png`, with
  names checked by the website's pattern, and only PNGs of at most 64 KB.
- The admin socket is an abstract Unix socket, which only processes inside
  the auth container can reach.
- The status page is refused for anything that came through Cloudflare. nginx
  is published on 127.0.0.1 only.
- Client addresses come from `Cf-Connecting-IP`, which Cloudflare sets
  itself, so visitors cannot forge them.
- 3D Armor's armour inventory lets only its owner put things in or take them
  out. Adventures and creative mode put armour aside and give it back with
  the rest.
- `npm audit`: nothing found in either service. nginx 1.30.6 has the October
  fixes. Luanti 5.18 is past the 2026 sandbox escapes (fixed in 5.15.2).

### For the operator

- **Node.js security release, due 11 November** (highest severity HIGH, lines
  22, 24 and 26). When it is out, move both Dockerfiles off
  `node:24.22.1-bookworm-slim` and rebuild auth, chain and proxy.
- **Turnstile.** Make sure `OV_TURNSTILE_SECRET` and `OV_TURNSTILE_SITEKEY`
  are set in production.
- **Cloudflare.** Turn on Bot Fight Mode. Add a rate-limiting rule for
  `/auth/` and `/api/` (for example 100 requests a minute per address).
  Remember "Under Attack" mode for a bad day.
- **Before restarting the proxy with patch 1104**, run `./characters.sh bans`
  once. This makes `OV_DATA/proxy` as your user; otherwise Docker makes it,
  owned by root.
- **Guests can chat.** Guests are anonymous and new on each visit. If chat
  abuse starts, the choices are: kick, ban the address, or take the `shout`
  privilege from guests.
- **The host** (outside this repository): keep unattended upgrades on, keep
  Docker up to date, use SSH keys only, and keep iLO on its own network.
