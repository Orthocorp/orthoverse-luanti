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
- Wallet sign-in and guests: wallet players build on the lands their wallet holds
  (ownership read from the Ethereum contract); guests explore. See `web/README.md`.
- Crofts (castle level 0) are open land: anyone can build there, but the holder
  owns it and can claim it at any time. Any player signed in (with a wallet, or a
  password character after its first hour of play), token or not, may mine and
  build there, and anyone may dig anyone's blocks; when the holder raises the
  castle level, the land and everything built on it is theirs alone. Guests cannot build. A futuristic level 8 land is not a croft (flipping
  the realm shows the holder takes part) until it is flipped back.
- Creative mode on your own lands from castle level 1: every block in the
  inventory's Creative tab and no damage. Your own inventory is put away while you
  are there and comes back when you step off; the creative one is kept for next
  time, so nothing from the Creative tab leaves the land. Higher levels add fly and
  fast (level 2) and noclip (level 3), in either realm. The table is `LEVELS` in
  `mods/orthoverse_creative/init.lua`.
- Rollback recording: an admin can see who changed a block (`/rollback_check`)
  and undo a player's changes (`/rollback <player> <seconds>`).
- Player skins: each character designs its own look on the website (the Account
  page's Character tab, with a 3D preview), and wears it in the game within
  seconds; see `web/README.md`. Guests wear one of Wizard, Elf, Borgo and Strider,
  picked from their name (to add one, put a 64 × 32 or 64 × 64 skin in
  `mods/orthoverse_skins/textures/` named `orthoverse_skin_<name>.png` and rebuild).
- Animals (Animalia): cows, sheep, horses, pigs and chickens on the natural lands,
  cats, rats, songbirds and owls, bats in caves and tropical fish in the sea; in the
  woods, wolves, foxes, reindeer, turkeys and opossums (`orthoverse_forest_animals`).
  Grizzly bears attack players and are off unless `orthoverse_bears` is true.
- The name of the land you are on at the bottom left of the screen, in the Midnight
  font as on the cards, with its crest
  and headgear above it as on the token card (crests from castle level 1).
- `/home [land]`: holders go to one of their own lands (any holder, no privilege needed;
  it replaces Minetest Game's `/home`).
- `/goto <land>`: teleport to a land by name (any part of it, accents optional) or
  by old coordinates such as `12:-3`, for players with the teleport privilege.
- The minimap for everyone, shown from the moment they join (no mapping kit needed);
  V cycles through close, wide and off. The radar (caves) is for the admin only.

Not yet: natural-looking terrain, real castle schematics.

## Layout

```
game.conf, minetest.conf     game definition and map defaults (flat mapgen, chunksize 6)
mods/mtg/                    Minetest Game mods, vendored by tools/assemble.sh
mods/animals/                Animalia and Creatura (animals), vendored by tools/assemble-animals.sh
mods/orthoverse_animals/     which animals spawn where in the Orthoverse
mods/orthoverse_skins/       player skins: the website's, and the guests'
mods/orthoverse_minimap/     the minimap for every player, on when they join
mods/orthoverse_landhud/     the land you are on and its crest, at the bottom left
texturepacks/                the look of the world for everyone (OV_TEXTURES in .env; see its README)
mods/orthoverse_wallets/     who may join (wallet players, guests) and who may build where
mods/orthoverse_creative/    creative mode on your own lands, abilities by castle level
mods/orthoverse_lands/       land data (data/lands.json) and coordinate helpers
mods/orthoverse_mapgen/      the land generator (runs in the engine's mapgen threads)
mods/orthoverse_nodes/       world edge, henge portal and gateway, tarmac
mods/orthoverse_henges/      henge gateways: teleporting between the nine henges
mods/orthoverse_admin/       /pregen and /orthomap, plus startup pre-generation
mods/orthoverse_adventure/   adventures: /adventure, the gate, runs, records, ranks, the death lockout
mods/orthoverse_combat/      hold-and-release fighting, the weapons, the training dummy
mods/orthoverse_wield/       what players hold, seen by others; the arm raised and swung in a fight
mods/orthoverse_bodies/      players and the bigger animals are solid; players put inside each other are parted
mods/orthoverse_monsters/    the adventure monsters and the monster spawner (on Mobs Redo, mods/mobs)
mods/orthoverse_rank/        character rank and experience
mods/orthoverse_loot/        loot chests, healing draughts, weapon recipes
source-data/                 snapshot files the land data is built from
tools/build_lands.py         rebuilds lands.json from source-data
tools/assemble.sh            refreshes mods/mtg from Minetest Game
tools/render_map.py          offline top-down render from map.sqlite
tools/mapslice.py            offline node counts and vertical slices (debugging)
tools/split_crests.py        one PNG per crest, for orthoverse_landhud (run by the image build)
tools/midnight_atlas.py      the Midnight font as a picture of its letters, for orthoverse_landhud
tools/make_logo.py           the Orthoverse logo and site icon, from the Midnight font
tools/make_desktop_art.py    the pixel-art computer on the play page for phones
tools/make_cave.py           the cave wall round the web map, from the game's textures
compose.yaml, docker/         running it all on Docker Compose (see docker/README.md)
web/                         orthoverse.land: site, map, proxy, browser game (see web/README.md)
docs/                        design documents: land abilities, accounts, adventures (see docs/README.md)
adventures/                  ready-made adventures for /adventure place (see adventures/README.md)
```

## Coordinates

- A land is 96 × 96 nodes (6 × 6 tiles of 16), centred on the origin: land 0:0
  covers x and z from −48 to 47. With `chunksize = 6`, one mapchunk is one land.
- Land keys use the old Orthoverse convention, `"x:z"` with z growing **south**.
  Luanti's z grows north, so the generator mirrors rows. North in the old world
  is still north here: Norhenge (0:−30) sits at Luanti z ≈ +2880.
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
python3 tools/split_crests.py web/heraldry mods/orthoverse_landhud/crests   # once: crests (needs Pillow)
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

## Running it

Everything (game server, web proxy, website, map drawing and the browser game
build) runs on Docker Compose from `compose.yaml`; see `docker/README.md`. On the
ProLiant, after a `git pull`: `docker compose up -d --build`. Changes to the
generator only affect land generated afterwards; regenerating the whole map is
described in `docker/README.md`.

## On the web

`web/` holds orthoverse.land: a landing page, a world map, and Luanti running in the
browser through a small WebSocket proxy. See `web/README.md`.

## Licences

Minetest Game (mods/mtg) is LGPL-2.1-or-later for code and CC BY-SA 3.0 for media;
see `mods/mtg/LICENSE-minetest_game.txt`. Animalia and Creatura (mods/animals) are MIT, by ElCeejo. In the browser game, Alegreya (web/client/fonts, by Juan Pablo del Peral and Huerta Tipográfica) is under the SIL Open Font License 1.1. Mesecons (mods/mesecons, the parts dungeons need) is LGPL-3.0 for code and CC BY-SA 3.0 for media, by the Mesecons Mod Developer Team. Mobs Redo (mods/mobs, the monster engine) is MIT, by TenPlus1; its few textures and sounds are CC0 or CC BY-SA 3.0 (see its license.txt). The monster skins and the mosslings', hexers' and wisps' sounds (mods/orthoverse_monsters, painted by tools/monsters, from esp32-s3-minetest) are CC BY-SA 3.0, by Keir Finlow-Bates, as are the weapon pictures (mods/orthoverse_combat, painted by tools/weapons/make_weapon_textures.py) and the healing draught's picture (mods/orthoverse_loot); the blow sounds (made by tools/weapons/make_blow_sounds.py) and the rank sounds (tools/rank/make_rank_sounds.py) are CC0. WorldEdit (mods/worldedit, core and commands, for the admin only) is AGPL-3.0, by sfan5 and contributors: the AGPL asks that its source be offered to the server's users, which this public repository does. Leaflet (web/site/map/vendor/leaflet) is BSD-2-Clause. Licence for the Orthoverse
mods and web code: to be decided.
