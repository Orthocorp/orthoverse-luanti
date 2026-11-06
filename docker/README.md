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
  │  map     on demand: draws the map from the world (read-only)            │
  │  client  on demand: builds and installs the browser game                │
  └──────────────────────────────────────────────────────────────────────────┘
       world: /mnt/ethereum/orthoverse/luanti/worlds/orthoverse (plain files)
       data:  /mnt/ethereum/orthoverse/data/{map,play}
```

The game server publishes no port, so the web proxy is the only way in, and the
`game` network has no route to the internet.

| Service | Image | What it does |
| --- | --- | --- |
| `luanti` | `docker/luanti/` | Luanti 5.18.0 server with static LuaJIT, the Orthoverse game; settings in `docker/luanti/orthoverse.conf` |
| `proxy` | `docker/proxy/` | `web/proxy/proxy.js` |
| `auth` | `docker/auth/` | Wallet sign-in, player names, land owners from the Ethereum contract; the only service with internet access |
| `web` | `docker/web/` | nginx with the landing and map pages; serves the map tiles and the browser game from `data/` |
| `map` | `docker/map/` | `docker compose run --rm --build map` redraws the map (about 4 minutes) |
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
| Redraw the map | `docker compose run --rm --build map` |
| Rebuild and install the browser game (engine patches or `play.html` changed) | `docker compose run --rm --build client` |
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
  kept: wallet players' game passwords are derived from it, so changing it locks
  them out of their players.
- `curl -s http://127.0.0.1:8485/auth/status` shows how many players are signed
  up, when land ownership was last read, and any error reading it.
- `docker compose logs auth` shows sign-ins, new names and each ownership update:
  `owners updated: N lands held by W player wallets; M of 1943 still with their
  2023 owner`. M should be in the hundreds; 0 means `OV_CONTRACT` or the RPC
  endpoint is wrong.
- Player names and wallets are in `OV_DATA/auth/registry.json`. Back it up with the
  world: without it, wallet players cannot join as their players.

## History: before Docker

Until 5 November 2026 the Orthoverse ran from systemd services and install
scripts (removed from the repository since; see the git history). The old
setup's leftovers under /mnt/ethereum/orthoverse can be deleted to free space:
`luanti/` apart from `luanti/worlds/` (the world lives there), `node/`, `venv/`,
`build/`, `game/`, `web/`, `orthoverse.conf` and `make-map.sh`. Keep `data/` and
`backups/`. The systemd unit files `/etc/systemd/system/orthoverse.service` and
`orthoverse-webproxy.service` and the nginx site
`/etc/nginx/sites-available/orthoverse-web.conf` can go too.
