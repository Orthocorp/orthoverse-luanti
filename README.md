# Orthoverse for Luanti

The Orthoverse rebuilt as a [Luanti](https://www.luanti.org) game. Every land is an
Orthoverse token: its terrain comes from the token ID, its position is frozen from
the 2023 map, and its level decides the castle (levels 1 to 7) or the flipped
tarmac realm with rockets (levels 8 to 15).

Built on Minetest Game, running on the standard C++ Luanti server.

## Status

First rough version of the world:

- All 1,943 lands from the last live snapshot (6 April 2023), in their original
  positions: nine island kingdoms of 15 × 15 lands, each round its henge.
- Each land's 36 tiles generated from its token ID: hills, mountains, lakes,
  woods, plains, quarries, deserts, badlands, and the flipped-realm sculptures.
- Sea for unrevealed land, the plains-and-mountains rim, and the world-edge wall.
- Placeholder castles (natural realm) and rockets (flipped realm), scaled by level.
- Henges as stone circles with four gateways: going through the north, south, east
  or west one takes you to the centre of the next henge that way (wrapping round at
  the edge of the 3 × 3 grid, as the old Orthoverse did).
- Caves, caverns, dungeons and ores underneath, from the engine's flat mapgen.

Not yet: natural-looking terrain, real castle schematics,
ownership and protection, wallet binding, the chain indexer.

## Layout

```
game.conf, minetest.conf     game definition and map defaults (flat mapgen, chunksize 6)
mods/mtg/                    Minetest Game mods, vendored by tools/assemble.sh
mods/orthoverse_lands/       land data (data/lands.json) and coordinate helpers
mods/orthoverse_mapgen/      the land generator (runs in the engine's mapgen threads)
mods/orthoverse_nodes/       world edge, henge portal and gateway, tarmac
mods/orthoverse_henges/      henge gateways: teleporting between the nine henges
mods/orthoverse_admin/       /pregen and /orthomap, plus startup pre-generation
source-data/                 snapshot files the land data is built from
tools/build_lands.py         rebuilds lands.json from source-data
tools/assemble.sh            refreshes mods/mtg from Minetest Game
tools/render_map.py          offline top-down render from map.sqlite
tools/mapslice.py            offline node counts and vertical slices (debugging)
tools/proliant/              install and pre-generation scripts for the ProLiant
```

## Coordinates

- A land is 96 × 96 nodes (6 × 6 tiles of 16), centred on the origin: land 0:0
  covers x and z from −48 to 47. With `chunksize = 6`, one mapchunk is one land.
- Land keys use the old Orthoverse convention, `"x:z"` with z growing **south**.
  Luanti's z grows north, so the generator mirrors rows. North in the old world
  is still north here: Pohjanhenge (0:−30) sits at Luanti z ≈ +2880.
- Tile index within a land: row (from the north) × 6 + column (from the west),
  matching hex digits 3 to 38 of the token ID.
- Playable lands run from −56 to 56; ring 57 is the rim, ring 58 the wall.

## Land data

`mods/orthoverse_lands/data/lands.json` is built from the snapshot:

```
python3 tools/build_lands.py source-data/voxel.json source-data/special.json \
    source-data/orthoverse-sqlite.dump mods/orthoverse_lands/data/lands.json
```

`voxel.json` is the land table the last live server used (identical in
orthoverse-offline and orthoverse-prismarine). Positions in it are authoritative
and frozen. `owner_snapshot` is the April 2023 owner and is not used for
permissions; current owners will come from the chain.

## Running locally

```
tools/assemble.sh                          # once: pull in Minetest Game mods
ln -s "$PWD" <luanti>/games/orthoverse     # make the game visible to Luanti
```

Create a world with game "Orthoverse" (flat mapgen is the only one allowed).
To pre-generate and render an overview from the command line, put these in the
server's config and start it:

```
orthoverse_pregen_radius = 3     # lands round the centre; 58 = the whole map
orthoverse_pregen_centre = 0,0   # old land coordinates
orthoverse_pregen_exit = true
orthoverse_render_map = true     # writes <world>/orthomap.ppm
```

In game, with the server privilege: `/pregen <radius>`, `/orthomap <radius>`,
and `/whereami` for anyone. For an overview of a big area, render offline:
`tools/render_map.py <world>/map.sqlite orthomap.png` (whole map: about 3 minutes).

## On Docker Compose

The whole Orthoverse (game server, web proxy, website, map drawing and the
browser game build) runs from `compose.yaml`: `docker compose up -d --build`.
See `docker/README.md`, including how to move over from the scripts below.

## On the ProLiant (scripts, before Docker)

See `tools/proliant/install.sh` (builds Luanti 5.18.0 with LuaJIT, creates the
`ovserver` user and world under `/mnt/ethereum/orthoverse`, installs a systemd
service pinned to NUMA node 0) and `tools/proliant/pregen.sh`.

After `git pull` on the ProLiant:

- `sudo ./tools/proliant/update.sh` copies the new game in and restarts the server.
  Changes to the generator only affect land generated afterwards.
- `sudo ./tools/proliant/regen.sh` regenerates the whole map with the current
  generator (about 25 minutes). Accounts survive; builds in the world do not, and
  the old map is kept in `backups/`.

## On the web

`web/` holds orthoverse.land: a landing page, a world map, and Luanti running in the
browser through a small WebSocket proxy. See `web/README.md`.

## Licences

Minetest Game (mods/mtg) is LGPL-2.1-or-later for code and CC BY-SA 3.0 for media;
see `mods/mtg/LICENSE-minetest_game.txt`. Leaflet (web/site/map/vendor/leaflet) is BSD-2-Clause. Licence for the Orthoverse
mods and web code: to be decided.
