# The Orthoverse on Docker Compose

Everything runs in containers, defined by `compose.yaml` in the repository root.
Only Docker and the Cloudflare tunnel are on the host.

```
browser ── https://orthoverse.land ──► Cloudflare tunnel (host) ──► 127.0.0.1:8485
                                                                      │
  ┌─────────────────────────── docker compose ────────────────────────┼──────┐
  │  web (nginx) ◄────────────────────────────────────────────────────┘      │
  │    /, /map/, /play/  static files                                        │
  │    /proxy ──► proxy (Node) ──► luanti (game server, no published port)   │
  │                 "web" network      "game" network (internal, no internet)│
  │                                                                          │
  │  map     on demand, mapwatch when lands are added: draws the map        │
  │  client  on demand: builds and installs the browser game                │
  └──────────────────────────────────────────────────────────────────────────┘
       world: /mnt/ethereum/orthoverse/luanti/worlds/orthoverse (plain files)
       data:  /mnt/ethereum/orthoverse/data/{map,play,auth,chain}
```

The game server publishes no port, so the web proxy is the only way in, and the
`game` network has no route to the internet.

| Service | Image | What it does |
| --- | --- | --- |
| `luanti` | `docker/luanti/` | Luanti 5.18.0 server with static LuaJIT, the Orthoverse game; settings in `docker/luanti/orthoverse.conf` |
| `proxy` | `docker/proxy/` | `web/proxy/proxy.js` |
| `auth` | `docker/auth/` | Wallet sign-in, player names, which player's wallet holds which land |
| `chain` | `docker/auth/` | Once a day: every token, its holder, castle level and realm, from the contract (`web/auth/chain.js`) |
| `web` | `docker/web/` | nginx with the landing and map pages; serves the map tiles and the browser game from `data/` |
| `map` | `docker/map/` | `docker compose run --rm --build map` redraws the map (about 4 minutes) |
| `mapwatch` | `docker/map/` | Every 5 minutes, draws again the map tiles, land pictures and token cards of the lands that changed |
| `client` | `docker/client/` | Builds luanti-wasm with `web/client/patches/` and installs it with `play.html` |

## Everyday use

All commands from the repository directory (`~/orthoverse-luanti`).

| To | Run |
| --- | --- |
| Update after a `git pull` | `docker compose up -d --build` |
| Restart the game server (after editing `docker/luanti/orthoverse.conf`) | `docker compose restart luanti` |
| Change the admin (`OV_ADMIN` in `.env`) | `docker compose up -d luanti` |
| See what is running | `docker compose ps` |
| Follow the logs | `docker compose logs -f luanti` (also `proxy`, `web`) |
| Redraw the whole map and every token card (after generating the world again, or a change to the card design; about 10 minutes) | `docker compose run --rm --build map` |
| Redraw only the lands that changed, now (mapwatch does it every 5 minutes) | `docker compose run --rm map update` |
| Rebuild and install the browser game (engine patches or `play.html` changed) | `docker compose run --rm --build client` |
| Put a changed `play.html` in place without building the game (the installed release stays) | `R=$(cat "$OV_DATA/play/RELEASE"); sed "s/%__RELEASE_UUID__%/$R/g" web/client/play.html \| sudo -u ovserver tee "$OV_DATA/play/index.html" >/dev/null` |
| Stop everything | `docker compose down` |

The client build only redoes what changed. The first build takes 20 to 40 minutes
(the Emscripten SDK and the support libraries). After that, a changed engine
patch recompiles only the changed files, and a changed `play.html` takes
seconds. Docker keeps the earlier stages, so do not prune the build cache unless
you want a clean build (`docker compose build --no-cache client`).

`--build` makes `run` rebuild the tool's image first when the repository has
changed; when nothing changed it costs a second.

### Regenerating the whole map

Anything built in the world is lost; accounts are kept. The old map goes to backups.

```
docker compose stop luanti
mv /mnt/ethereum/orthoverse/luanti/worlds/orthoverse/map.sqlite \
   /mnt/ethereum/orthoverse/backups/map-$(date +%Y%m%d-%H%M).sqlite
docker compose run --rm luanti pregen          # about 25 minutes; pregen 3 0,0 for a quick test
docker compose start luanti
docker compose run --rm --build map
```

### New lands

A token revealed after the world's lands were fixed gets a land of its own,
by itself:

1. The `chain` service, in its daily run, gives it the next free cell in the
   order the old toolchain used (`generate-map-from-db-sqlite.js`): a square
   spiral round each of the nine henge centres, all nine growing together,
   skipping lands and the planned seas and lakes (`seas` in
   `mods/orthoverse_lands/data/lands.json`, from the old `sea.json`). The next
   cells are -7:4, -37:-26, -7:-26, 23:-26, -37:4. It names the land as
   `load-tokens.js` did, and writes `OV_DATA/chain/new-lands.json`. A land, once
   placed, never moves (table `placements` in the chain database).
2. Within a minute the game adds it, and makes its terrain: it deletes the
   land's mapchunk and those of the sea cells around it, and generates them
   afresh (`docker compose logs luanti | grep orthoverse_lands`). Neighbouring
   lands are not touched: lands run full height to their edges, and the beaches
   are in the sea cells.
3. The auth service adds it within 10 minutes, so its holder can build there.
4. `mapwatch` redraws the web map a few minutes later.

### Castle levels

Lands are built from their current castle level, not the 2023 one in
`lands.json`: the `chain` service writes every land's level to
`OV_DATA/chain/land-levels.json` each day, and the game, checking every minute,
makes a land again when its level has changed (a castle built up, or the realm
flipped), four at a time (`docker compose logs luanti | grep "made again"`).
Only that land's mapchunk is made again, and only the tiles of it (16 x 16,
36 to a land) that nobody has built on: the game records every tile where a
player has placed or dug a block, and keeps those tiles exactly as they are,
chests and furnaces included. So a castle whose tiles have been built on keeps
its old shape there. Lands built on before tiles were recorded (November 2026)
are kept whole. The log says how many tiles were kept ("made again at level 5,
2 of 36 tiles kept as built").

### The admin and privileges

The admin is a wallet player: sign in with your wallet on the play page, choose
your player name, put that name in `OV_ADMIN` in `.env`, and run
`docker compose up -d luanti`. That player has every privilege, and can build
anywhere. In the game (chat, T) the
admin can give other players some of them, for example
`/grant somebody fly,fast,noclip`, take them away with `/revoke somebody fly`,
and see a player's with `/privs somebody`. In the game, fly is toggled with K,
fast with J and noclip with H.

### Wallet sign-in and ownership

- `OV_AUTH_SECRET` in `.env` must be set once (`openssl rand -hex 32`) and then
  kept: it signs everyone's sign-ins, so changing it signs everyone out (they
  sign in again; game passwords are made fresh for each entry, so nothing else
  is lost).
- `curl -s http://127.0.0.1:8485/auth/status` shows how many players are signed
  up, when land ownership was last read, and any error reading it.
- `docker compose logs auth` shows sign-ins, new names and each ownership update:
  `owners updated: N lands held by W player wallets; M of 1943 held as the chain
  index says`. M should be nearly all of them (before the chain service's first
  run it compares with the 2023 snapshot instead); 0 means `OV_CONTRACT` or the
  RPC endpoint is wrong.
- Each day the `chain` service reads the contract's new transfer events and every
  castle level into `OV_DATA/chain/`: `orthoverse-chain.sqlite` (tables `tokens`,
  `transfers`, `meta`), `tokens.json`, and `token-data.json` in the format of the
  old `scrape-tokenids-and-levels.js` (`[holder, level, tokenId, revealBlock]`).
  With an Alchemy endpoint it reads transfers with `alchemy_getAssetTransfers`,
  the whole history since 2022 in a few calls. With any other endpoint it uses
  `eth_getLogs` from the Merge (September 2022; most nodes no longer keep older
  logs) on top of the lands' 2023 snapshot, which takes much longer on endpoints
  that allow few blocks per call, and leaves out tokens revealed before the Merge
  that have no land in the world. Later runs read only the new blocks.
  `docker compose logs chain` shows each run (`chain indexed to block ...`), and
  `docker compose restart chain` runs it now.
  The auth service checks each land's indexed holder, so `/whereami` names the
  real holder. Levels 0 to 7 are the fantasy realm, 8 to 15 the futuristic one.
  To look at the data: `sqlite3 /mnt/ethereum/orthoverse/data/chain/orthoverse-chain.sqlite
  "SELECT holder, count(*) FROM tokens GROUP BY holder ORDER BY 2 DESC LIMIT 10"`.
- Player names and wallets are in `OV_DATA/auth/registry.json`. Back it up with the
  world: without it, wallet players cannot join as their players.

### Adventures

Holders of a land at castle level 5 or more, and the admin anywhere, build
adventures with `/adventure` in the game (it lists its commands): create one,
mark the dungeon area's corners, the start inside it and the arrival point
outside it, place the gate (near the arrival point) and the finish (inside), then
`/adventure save` and `/adventure open`. One party at a time; the dungeon is
restored from its saved version after each run. Saved dungeons and records are in
`OV_WORLD/orthoverse_adventures/` (covered by the nightly backup); the website's
Adventures page reads `adventures.json` there through the auth service
(`/api/adventures`). The admin has WorldEdit for building them (`//help`).

### Characters with a name and password

- Players without a wallet make a character on the site (Sign in, then Make a
  character) with a name and password, and are shown a recovery code once.
  A wallet can be linked to it later on the Account page, and wallet players can
  add a password there. They are in `registry.json` too, with only scrypt hashes
  of the password and recovery code; the game password is made fresh for each
  entry, as for wallets.
- Characters without a wallet mine and build on crofts after their first hour of
  play (counted by the game); with a wallet, at once.
- At most three new characters per address per day; ten wrong passwords for a
  name rest it for 15 minutes.
- The "are you a robot" check (Cloudflare Turnstile) is optional: create a
  Turnstile widget for orthoverse.land in the Cloudflare dashboard, put its keys
  in `OV_TURNSTILE_SITEKEY` and `OV_TURNSTILE_SECRET` in `.env`, and
  `docker compose up -d auth`. On the play page (which cannot load Cloudflare's
  script) registration is then sent to the Account page.
- A player who has lost both their password and their recovery code: if their
  character has a wallet, they sign in with it and set a new password on the
  Account page. Otherwise the admin gives them a new recovery code:
  `docker compose stop auth`, then
  `docker compose run --rm auth node recovery-code.js <name>`, then
  `docker compose start auth` (check first that the request is genuine).
