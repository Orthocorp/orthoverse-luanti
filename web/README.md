# The Orthoverse on the web

Everything served at orthoverse.land:

| Path | What it is |
| --- | --- |
| `/` | Landing page |
| `/map/` | Zoomable map of the whole world, with land search and land details |
| `/play/` | Luanti running in the browser (paradust7/luanti-wasm), joined to the Orthoverse |
| `/proxy` | WebSocket the browser client uses to reach the game server |

```
browser ── https://orthoverse.land ──► Cloudflare tunnel ──► nginx 127.0.0.1:8484
                                                              ├─ /, /map/, /play/   static files
                                                              └─ /proxy  ──► web proxy 127.0.0.1:8737
                                                                               └─ UDP ──► Luanti 127.0.0.1:30000
```

Browsers cannot send UDP, which Luanti uses. The browser client wraps its UDP
traffic in a WebSocket; `web/proxy/proxy.js` unwraps it and passes it to the
Luanti server on the same machine. The proxy reaches nothing else: datagrams to
any other address are dropped, it relays no TCP, and its name resolver only
knows the Orthoverse's own names. Because the game traffic travels through the
Cloudflare tunnel, browser players need no port forwarding on the router.

## Parts

| Directory | Contents |
| --- | --- |
| `web/proxy/` | The web proxy (Node, one dependency: `ws`), and `test/handshake.js` |
| `web/client/` | `build.sh` builds luanti-wasm at a pinned commit, with the engine changes in `patches/`; `play.html` is the Orthoverse play page it installs |
| `web/map/make_tiles.py` | Map tiles and the land list, from the world database |
| `web/site/` | Landing page and map page (Leaflet 1.9.4, vendored) |
| `web/nginx/`, `web/systemd/` | nginx site and proxy service, filled in by the installer |
| `tools/proliant/install-web.sh` | Installs all of the above on the ProLiant |
| `tools/proliant/make-map.sh` | Refreshes the map from the live world |

## Installing on the ProLiant

1. `git pull`, then `sudo ./tools/proliant/install-web.sh` (about 10 minutes, most of it
   rendering the map).
2. Build the browser client (15 to 30 minutes the first time):
   `sudo -u ovserver /mnt/ethereum/orthoverse/game/web/client/build.sh`
3. Check locally: `curl -sI http://127.0.0.1:8484/play/ | head -1` should say `200`.
4. Put orthoverse.land on the Cloudflare tunnel (below).

### Cloudflare tunnel

The site listens on 127.0.0.1:8484 only; the existing `home-web` tunnel brings it
to the internet.

1. Add a rule to `/etc/cloudflared/config.yml`, above the final catch-all rule:
   ```yaml
     - hostname: orthoverse.land
       service: http://127.0.0.1:8484
     - hostname: www.orthoverse.land
       service: http://127.0.0.1:8484
   ```
   then `sudo systemctl restart cloudflared`.
2. In the Cloudflare dashboard, zone **orthoverse.land**, DNS: replace any old
   `orthoverse.land` and `www` records with proxied CNAMEs to
   `<tunnel id>.cfargotunnel.com` (the tunnel id is the `tunnel:` line in
   `config.yml`). Do this in the dashboard: `cloudflared tunnel route dns` on this
   machine creates records in the blockchaingandalf.com zone.
3. Optional but worth it: a Cache Rule for `orthoverse.land/play/*` set to
   "Eligible for cache". Cloudflare does not cache `.wasm` and `.pack` files by
   default, so without it every new player downloads the engine over the 5G link.
   The release files are named per build, so caching them forever is safe.

WebSockets work through the tunnel with no extra settings.

## Running it

- Service: `systemctl status orthoverse-webproxy`, log with `journalctl -u orthoverse-webproxy`.
- Refresh the map after building or regenerating: `sudo -u ovserver /mnt/ethereum/orthoverse/make-map.sh`.
- Update site or proxy after a `git pull`: re-run `install-web.sh`.
- Rebuild the browser client: re-run `build.sh`. The newest two builds are kept, so
  players mid-load are not broken by an update.

## Limits and settings

Set in the service file (`/etc/systemd/system/orthoverse-webproxy.service`):

| Setting | Default | Meaning |
| --- | --- | --- |
| `OV_MAX_SOCKETS` | 100 | Browser players at once |
| `OV_MAX_PER_IP` | 6 | Connections from one address |
| `OV_VIRTUAL_IP` | 10.58.0.1 | Address the browser client dials; must match `play.html` |
| `OV_IDLE_SECONDS` | 120 | Silent connections are closed after this |

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

## Web only

`install-web.sh` sets `bind_address = 127.0.0.1` in `orthoverse.conf`, so the
Luanti server listens on the ProLiant itself and nowhere else: the web proxy is
the only way in. A desktop Luanti client on the LAN or the internet cannot
connect, even if UDP 30000 were forwarded. To open it up again, delete that line
and `sudo systemctl restart orthoverse` (or install with `WEB_ONLY=0`).

Every browser player reaches the Luanti server from 127.0.0.1, so the server
cannot tell them apart by address: ban browser players by name, not by IP.

## Tested here, and not

- **Tested:** the proxy against a real Luanti 5.18 server, directly and through
  nginx (`web/proxy/test/handshake.js`: a Luanti handshake gets the server's
  reply; foreign addresses, foreign names and TCP are refused); `install-web.sh`
  end to end in a container; the landing, map and play pages in Chromium through
  nginx, including the headers that let the client use threads.
- **Not tested:** building luanti-wasm itself, and so a real browser session. The
  build downloads the Emscripten SDK and Node from sites this environment cannot
  reach. The proxy speaks the protocol of the exact webshims revision the pinned
  luanti-wasm commit uses, and the play page uses the launcher API of that commit.
