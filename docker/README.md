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

The player named in `OV_ADMIN` has every privilege. In the game (chat, T) the
admin can give other players some of them, for example
`/grant somebody fly,fast,noclip`, take them away with `/revoke somebody fly`,
and see a player's with `/privs somebody`. In the game, fly is toggled with K,
fast with J and noclip with H.

## Moving from the old setup

The old setup (systemd services `orthoverse` and `orthoverse-webproxy`, the nginx
site on 8484) keeps running until step 6, and stays installed until step 9, so you
can go back at any point before that.

1. **Docker.** Check it is there with `docker compose version`. If not:
   `sudo apt install docker.io docker-compose-v2`, then `sudo usermod -aG docker $USER`,
   and log out and in again.

2. **Settings.** In `~/orthoverse-luanti`:
   ```
   cp .env.example .env
   id -u ovserver; id -g ovserver
   ```
   Put the two numbers into `OV_UID` and `OV_GID` in `.env`, and your player name
   into `OV_ADMIN`. The other values are right for the ProLiant.

3. **Data directories**, with the map and the browser game copied over from the
   old setup, so nothing needs rebuilding yet:
   ```
   sudo mkdir -p /mnt/ethereum/orthoverse/data/map /mnt/ethereum/orthoverse/data/play
   sudo cp -a /mnt/ethereum/orthoverse/web/site/map/tiles /mnt/ethereum/orthoverse/web/site/map/lands.json /mnt/ethereum/orthoverse/data/map/
   sudo cp -a /mnt/ethereum/orthoverse/web/play/. /mnt/ethereum/orthoverse/data/play/
   sudo chown -R ovserver:ovserver /mnt/ethereum/orthoverse/data
   ```

4. **Build the images** (the game server takes about 10 minutes):
   ```
   docker compose build
   ```

5. **Back up the world**, since two servers must never use it at once:
   ```
   sudo systemctl stop orthoverse
   sudo cp -a /mnt/ethereum/orthoverse/luanti/worlds/orthoverse /mnt/ethereum/orthoverse/backups/world-before-docker
   ```

6. **Switch the game over.** Stop the old proxy and start the containers. Browser
   play is down from here until step 8, a few minutes:
   ```
   sudo systemctl stop orthoverse-webproxy
   docker compose up -d
   docker compose logs luanti | tail -5
   ```
   The log should end with `listening on 0.0.0.0:30000`, after `Pinned to NUMA node 0`.

7. **Check it locally** through an SSH tunnel from your desktop:
   `ssh -N -L 8485:127.0.0.1:8485 kf106@192.168.68.237`, then open
   http://localhost:8485/play/ and log in.

8. **Point the tunnel at it.** In `/etc/cloudflared/config.yml`, change both
   orthoverse.land rules from `http://127.0.0.1:8484` to `http://127.0.0.1:8485`, then
   `sudo systemctl restart cloudflared`. Check https://orthoverse.land/play/.

9. **Retire the old setup** once you are happy:
   ```
   sudo systemctl disable orthoverse orthoverse-webproxy
   sudo rm /etc/nginx/sites-enabled/orthoverse-web.conf && sudo systemctl reload nginx
   ```
   Later, once nothing points at them, `luanti/` (the source build, apart from
   `worlds/`), `node/`, `venv/`, `build/`, `game/` and `web/` under
   /mnt/ethereum/orthoverse can be deleted to free space.

**Going back** before step 9: `docker compose down`, point the tunnel back at 8484,
`sudo systemctl start orthoverse orthoverse-webproxy`.

From then on, `docker compose run --rm --build client` replaces `web/client/build.sh`,
and `docker compose run --rm --build map` replaces `make-map.sh`.
