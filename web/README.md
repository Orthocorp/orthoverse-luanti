# The Orthoverse on the web

Everything served at orthoverse.land:

| Path | What it is |
| --- | --- |
| `/` | Landing page |
| `/map/` | Zoomable map of the whole world, with land search and land details |
| `/play/` | Luanti running in the browser (paradust7/luanti-wasm), joined to the Orthoverse |
| `/proxy` | WebSocket the browser client uses to reach the game server |
| `/auth/` | Wallet sign-in and player names (the auth service) |

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
| `web/auth/` | Wallet sign-in, player names and land ownership (Node, `ethers`), and `test/auth.test.js` | `auth` |
| `web/site/` | Landing page and map page (Leaflet 1.9.4, vendored) | `web` |
| `web/map/make_tiles.py` | Map tiles and the land list, from the world database | `map` |
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
  stays bound to that wallet. The game password for the name is derived from a
  secret only the auth service holds (`OV_AUTH_SECRET`), so players never see or
  type a password, and only the wallet can obtain it.
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
each land's 2023 owner (`owner_snapshot` in the lands file) still does, and writes
`owners.json`. A land held by anyone else is "not held by a player here", and nobody
can build on it. A sale moves building rights within 10 minutes, and a wallet's
lands are looked up at once when it signs in. If the endpoint is down, the last
good list is kept. Check it with `curl -s http://127.0.0.1:8485/auth/status`.

The auth service writes `registry.json` (names and wallets) and `owners.json` to
`OV_DATA/auth/`, which the game server reads (read-only) as
`/world/orthoverse_auth/`.

The engine gets `--login` or `--register` from the page (added by
`patches/luanti-login-register.patch`), so a player is created in the game on
their first visit only. When joining fails, the engine hands the reason to the
page (`orthoverseJoinError`), the page reloads, and explains what went wrong.
The engine runs in English so the reasons can be recognised.

## Web only

The game server publishes no port and sits on an internal Compose network, so
the web proxy is the only way in: a desktop Luanti client on the LAN or the
internet cannot connect.

Every browser player reaches the game server from the proxy's address, so the
server cannot tell them apart by address: ban players by name, not by IP.

## Accounts

The play page has two tabs. **Log in** only logs in to an existing player: an
unknown name is refused, it never creates a player. **Register** only creates a
new player: a name that is taken is refused. The page passes `--login` or
`--register` to the engine (added by `patches/luanti-login-register.patch`; the
engine already had both modes for its own main menu, but no way to choose them
from the command line).

When joining fails, the engine hands the reason to the page
(`orthoverseJoinError`), the page reloads, and the form shows what went wrong
and what to do: unknown name, name taken (or the same name in other capitals),
wrong password, already playing, server full, server restarting, server not
reachable, client out of date. The engine runs in English so the reasons can be
recognised; anything unrecognised is shown as the engine's own text.

The server requires a password for every player (`disallow_empty_password`), and
the page asks for at least 6 characters when registering.

The choice is enforced by the web client, not the server: someone who builds
their own client could still create a player by logging in with a new name. The
server cannot tell the two apart, because a Luanti client asks to register only
after the server has told it the name is new.

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

WebSockets work through the tunnel with no extra settings.
