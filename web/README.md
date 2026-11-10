# The Orthoverse on the web

Everything served at orthoverse.land:

| Path | What it is |
| --- | --- |
| `/` | Landing page |
| `/map/` | Zoomable map of the whole world, with land search and land details |
| `/play/` | Luanti running in the browser (paradust7/luanti-wasm), joined to the Orthoverse |
| `/account/` | Account: your lands (upgrade a castle with `upgradeCastleLevel`, flip the realm with `flipRealm`), revealing your own land (`reveal`), and for anyone: gift an upgrade to any land, or give a land to any address (`gift`). `/lands/` sends here |
| `/css/site.css`, `/js/site.js` | What every page shares: the header (logo, Map, Account, Play, and signing in, with a player name chosen the first time), the footer, the wallet code |
| `/proxy` | WebSocket the browser client uses to reach the game server |
| `/auth/` | Wallet sign-in and player names (the auth service) |
| `/api/metadata/` | Token and collection metadata, for the contract's `uri()` and `contractURI()` (the auth service) |
| `/auth/visit` | POST `{x, z}`: arrive at that spot when you next join the game, within 10 minutes ("Visit this spot" on the map: the admin, `OV_ADMIN`, and holders of a level 7 land; the game checks again) |
| `/api/reveal/check`, `/api/reveal/status` | POST `{address}` after a reveal or gift: checks on the contract that the token is revealed and asks the chain service to index now (`index-now` in the auth data, which the chain service watches), so the land is placed within a minute or two; GET `?address=` says whether its land has been placed, and where |
| `/api/levels/check` | POST `{key}`: read one land's castle level from the contract now and hand it to the game (`levels.json` in the auth data), so an upgrade or flip is built within a minute instead of after the daily chain run |
| `/map/lands/` | Each land from above, 384 pixels square (drawn with the map) |
| `/map/cards/` | The token pictures (drawn with the map) |

It all runs on Docker Compose; how to run it is in `docker/README.md`. This file
is about how the web parts work.

Browsers cannot send UDP, which Luanti uses. The browser client wraps its UDP
traffic in a WebSocket; `web/proxy/proxy.js` unwraps it and passes it to the
game server. The proxy reaches nothing else: datagrams to any other address are
dropped, it relays no TCP, and its name resolver only knows the Orthoverse's own
names. Because the game traffic travels through the Cloudflare tunnel, players
need no port forwarding on the router.

## Parts

| Directory | Contents | Image |
| --- | --- | --- |
| `web/proxy/` | The web proxy (Node, one dependency: `ws`), and `test/handshake.js` | `proxy` |
| `web/auth/` | Wallet sign-in, player names and land ownership (Node, `ethers`, `pngjs`); `metadata.js`, the token metadata; `classic.js` and `classic/`, the classic pictures; `chain.js`, the daily chain index; tests in `test/` | `auth`, `chain` |
| `web/heraldry/` | The crests (from orthoverse-offline) | `auth`, `chain` |
| `web/site/` | Landing page and map page (Leaflet 1.9.4, vendored) | `web` |
| `web/map/make_tiles.py`, `cards.py` | Map tiles, land pictures, token pictures and the land list, from the world database | `map`, `mapwatch` |
| `web/client/play.html` | The Orthoverse play page | `client` |
| `web/client/patches/` | Orthoverse changes to the engine, applied when the browser game is built | `client` |

## Web only

The game server publishes no port and sits on an internal Compose network, so
the web proxy is the only way in: a desktop Luanti client on the LAN or the
internet cannot connect.

Every browser player reaches the game server from the proxy's address, so the
server cannot tell them apart by address: ban players by name, not by IP.

## Players: wallets and guests

The play page offers two ways in.

- **Sign in with wallet.** The page asks the wallet (MetaMask or any browser wallet)
  to sign a Sign-In with Ethereum message (EIP-4361) for this site; this costs
  nothing. The auth service (`web/auth/`) checks the signature and keeps the
  browser signed in for 30 days. The first time, the player chooses a name, which
  stays bound to that wallet. Each time a player enters the game, the auth
  service makes a fresh game password for that one entry, which the page hands
  to the game; players never see or type it, and the game lets each in once.
- **Play as a guest.** The page makes up a name like `Guest-7F3A9C` and a random
  password, kept in that browser so the guest comes back as the same player.

Old name-and-password accounts can no longer join: the game turns away any name
that is neither a guest nor bound to a wallet.

Building (`mods/orthoverse_wallets`): a wallet player can dig and build only on
the lands whose token the wallet holds now, ground below and sky above included.
Guests can explore, ride and use the henges but not build. Nobody builds on
henges, the open sea or the rim, except the admin. In the game, `/mylands` lists
your lands and `/whereami` says whose land you are on.

Ownership comes from the Orthoverse contract on Ethereum mainnet (`OV_CONTRACT`,
`0x118aeD2606D02C2545C6D7D2d1021e567cc08922`). It is an ERC-1155 with one token per
land, whose ID is the address that revealed it. An ERC-1155 cannot say who holds a
token, only whether a given wallet does (`balanceOf`, here always 0 or 1). So every
10 minutes the auth service asks, with `balanceOfBatch` through a public RPC
endpoint (`OV_ETH_RPC`), whether each player's wallet holds each land, and whether
each land's known holder still does, and writes `owners.json`. The known holder
comes from the daily chain index (`web/auth/chain.js`, the `chain` service, which
replays the contract's TransferSingle and TransferBatch events and reads every
`castleLevel`), or before its first run from the 2023 snapshot (`owner_snapshot`
in the lands file). A land held by anyone else is "not held by a player here", and nobody
can build on it. A sale moves building rights within 10 minutes, and a wallet's
lands are looked up at once when it signs in. If the endpoint is down, the last
good list is kept. Check it with `./status.sh` on the server (the status page
answers only there, not through Cloudflare).

The auth service writes `registry.json` (names and wallets) and `owners.json` to
`OV_DATA/auth/`, which the game server reads (read-only) as
`/world/orthoverse_auth/`.

## Skins

Each character designs one look on the Account page (Character tab): skin
tone, eyes, hair, beard, top, trousers and boots, each with a colour from its
palette, and accessories, some of which need a castle (the Borgo hat from
level 1, diadems from 5, coronets from 6, crowns from 7: the highest level among
the lands the character's wallet holds; the admin has them all). The page
shows it on the game's figure in 3D (skinview3d, MIT, in `site/js/vendor/`).
The parts are Ready Player Doomed's, the Orthoverse avatar designer
(Orthocorp, CC BY-SA 3.0), in `web/skin/parts/`.

The page sends only the design (`POST /auth/skin`). The auth service checks it,
paints the picture itself from the same parts with the same code as the page
(`web/skin/skin.js`), so nobody uploads a picture, and writes it to
`OV_DATA/auth/skins/<name>.png` in the game's 64 x 32 layout (the hat layer
kept; the outer layers of body, right arm and right leg painted onto them;
the model mirrors the right arm and leg for the left), with the design and
the picture's hash in `registry.json`.

The game (`mods/orthoverse_skins`) sees the new hash within 15 seconds and
sends the picture to every client while it runs (dynamic media, under a new
name for each version), then puts it on the player, so players already in the
game see the new look without reloading. Nobody chooses a skin in the game.
Guests, who cannot design one, wear one of the built-in skins, picked from
their name; a character with no design yet wears the default.

The engine gets `--login` or `--register` from the page (added by
`patches/luanti-login-register.patch`), so a player is created in the game on
their first visit only. When joining fails, the engine hands the reason to the
page (`orthoverseJoinError`), the page reloads, and explains what went wrong.
The engine runs in English so the reasons can be recognised.

## Token metadata

The contract builds its URIs from two base URIs, which its owner sets with
`setURI` and `setVoidURI`: `contractURI()` is `<base>contract.json`, and
`uri(id)` is `<base><id in hex>-<castle level>.json`, with the revealed base for
revealed tokens and the void base for the rest. Both bases are
`https://orthoverse.land/api/metadata/` (`web/auth/metadata.js`):

| Path | What |
| --- | --- |
| `contract.json` | The collection: name, description, picture, link, and the 2.5% royalty to the contract's owner (`royaltyInfo`) |
| `<0xid>-<level>.json` | A token. A land: its name, description, picture, a link to it on the map, and its realm, title, castle level, crest (the blazon), terrain, coordinates, whether it is an original or a new land, and its reveal block. A revealed token whose land is not placed yet says so; any other address is an unrevealed land |
| `crest/<n>-<rank>.png` | Crest n, 320 x 512 pixels, with no headgear, a baron's cap, a coronet or a crown above it |
| `classic/<0xid>-<level>[-unrevealed].png` | The classic pixel-art picture of a token, 800 x 800 |

The level in the URL is the level when a marketplace asked; the current level
from the chain index wins. `uri()` writes the ID without leading zero bytes, so
the API pads it back to 40 digits.

Pictures:

- A placed land's picture is its card (`web/map/cards.py`): the land drawn
  isometrically from the world itself, block by block (so overhangs, arches
  and poles look as built; plants, torches and other non-cube blocks are left
  out), with whatever its holder has built, on
  the old pictures' background colour for its realm, under a banner with its
  crest (a baron's cap at castle level 4, a coronet at 5 and 6, a crown at 7),
  name, title and coordinates, in the Midnight font (`web/map/fonts/`, the Lords
  of Midnight 8 x 8 font, at multiples of 8 pixels so it stays sharp). Blocks
  are coloured as on the map: natural ones from the palette in
  `tools/render_map.py`, everything else (what players build with) from the
  average colour of its texture, worked out when the map image is built
  (`tools/texture_colours.py`). The map service draws them all when it draws the
  whole map, and mapwatch every 5 minutes draws again those of lands that
  changed: the game lists the lands where blocks were placed or dug, or that
  were made again or added (`orthoverse_changed_lands.json` in the world), and
  a card is also drawn again when its level or crest changes on the chain. A
  land is drawn again a minute after the last change to it. They go to
  `OV_DATA/map/cards/`,
  each named after its content, so a changed picture gets a new address and
  marketplaces fetch it again; `cards/index.json` says which is current.
- A token with no land to draw (revealed but not placed yet, or unrevealed) gets
  the classic picture (`web/auth/classic.js`), drawn from its ID and level as
  orthoverse-offline's `make-map-image.js` drew each land on the old map, from
  the same tile art (`web/auth/classic/`); unrevealed ones in grey.

Crests are given out by the chain service as `update-escutcheons.js` did:
castle levels 1 to 3 get a plain crest, level 4 and up one with an animal (a
plain one is swapped then), never one already used. The 13,188 crests made by
orthoverse-offline's `make-shields.js` are in `web/heraldry/escutcheons.png`,
128 to a row, with their blazons in `heraldry.json`.

### Telling OpenSea

Marketplaces keep their own copy of each token's metadata and picture, so a
land that changes (built on and drawn again, a castle upgrade, a crest) looks
the same there until it is fetched again. With an OpenSea API key in `.env`
(`OV_OPENSEA_KEY`; opensea.io > Settings > Developer), the auth service
(`web/auth/opensea.js`) checks every 20 minutes (`OV_OPENSEA_EVERY_MIN`) which
lands' metadata differs from what OpenSea was last asked to show, and asks
OpenSea to refresh those. Without a key it asks nothing.

- The first run only notes what every land shows: do a complete collection
  refresh on OpenSea by hand, as the collection's owner, once.
- It keeps within OpenSea's limits: at most 60 refreshes a run, spaced out,
  stopping when OpenSea's count of calls left is low (the rest waits for the
  next run); a "too many" answer waits as long as OpenSea asks; three failures
  in a row pause it for an hour; a refused key pauses it for six hours. The
  queue is kept in `OV_DATA/auth/opensea.json` (never the key), so a restart
  loses nothing.
- `./status.sh` (on the server) shows how it is doing: the last
  run, how many are waiting, how many refreshed, any pause and why, and the
  limits OpenSea last reported.

## Proxy settings

Set in `.env` (the first two) or `compose.yaml`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `OV_MAX_SOCKETS` | 100 | Browser players at once |
| `OV_MAX_PER_IP` | 6 | Connections from one address |
| `OV_VIRTUAL_IP` | 10.58.0.1 | Address the browser client dials; must match `play.html` |
| `OV_IDLE_SECONDS` | 120 | Silent connections are closed after this |

## Cloudflare

The `web` container listens on 127.0.0.1:8485; the host's `home-web` tunnel
brings it to the internet.

- `/etc/cloudflared/config.yml` has rules for `orthoverse.land` and
  `www.orthoverse.land` pointing at `http://127.0.0.1:8485`, above the catch-all.
- DNS (in the dashboard, zone orthoverse.land): proxied CNAMEs for `@` and `www`
  to `<tunnel id>.cfargotunnel.com`. `cloudflared tunnel route dns` on the
  ProLiant would put them in the blockchaingandalf.com zone instead.
- A Cache Rule makes `orthoverse.land/play/*` eligible for cache, with the edge
  TTL from the cache-control header. Cloudflare does not cache `.wasm` and `.pack`
  files by default; the release files are named per build, so caching them for
  good is safe, and the page itself is marked not to be cached.

Map tiles are in a folder per drawing of the map (`/map/tiles/<version>/`),
and `lands.json` (never cached) names the current one, so a redrawn map shows at
once and tiles can be cached for good; the previous drawing is kept for pages
loaded a moment before. When only some lands are drawn again, the new version
is made of hard links to the current one, with just their tiles replaced.

WebSockets work through the tunnel with no extra settings.
