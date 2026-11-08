# Findings from the old Orthoverse code

> **Historical**: notes from reading the old flying-squid code on 2 Nov 2026, kept for the world geometry and generation rules. Since then the henges have English names (patch 0062: Norhenge, Southenge and so on), and the browser client was solved with luanti-wasm.

Sources: github.com/Orthocorp/orthoverse-prismarine (last updated May 2023), and the private orthoverse-offline repo (map toolchain and database, last updated Apr 2023). Reviewed 2 Nov 2026.

## Status of the old services

Everything is shut down: the orthoverse.io API, the avatars server and the old servers are gone. What remains is the source code and the orthoverse.land domain. The contracts are still on chain:

- Ethereum mainnet: `0xeDDe09C51343252fC83B9e5b6dE195A055AAcB56`
- Polygon: `0x5A47A6E082d01EC274E11eAB0808Fa2F8aff5b2C` (redeployed 23 Jan 2022)
- Rinkeby (test, defunct): `0x46DaEaC096fEf5a81a851e36c1744184eea83d8A`

## Stack (old)

- Server: flying-squid (PrismarineJS, Node 16) speaking the Minecraft 1.15.2 protocol, patched with plugins: `hengeportals`, `ethereum`, `generateNames`, plus changes to digging, placeBlock, login, commands, world, tp, daycycle.
- Client: prismarine-web-client, so players played in the browser with no install. Custom GUI art (crowns, compass, palantir, escutcheons) in `extra-textures`.
- Skins came from a separate Orthoverse Avatars server; wallet login via auth-orthoverse (RedwoodJS + WalletConnect signing).
- Land data came from the orthoverse.io API, which was itself built by the orthoverse-offline toolchain.

## orthoverse-offline (the map toolchain)

- Pipeline: scrape token IDs and levels from the chain (hardhat script in ricp/orthoverse-contracts), load into SQLite, recalculate adjusted heights, update crests, assign coordinates, render the big map image and Deep Zoom tiles.
- `orthoverse-sqlite.dump` holds the land table: 1,859 lands with coordinates (−37..37 on both axes), 1,815 distinct owners, reveal block heights up to 15,429,200. Columns: tokenId, blockheight, x, y, rank, name, special, level, adjustedheight, owner, crest, description. Specials: origin (Orthohenge), eight compass henges, four "prize" lands.
- Old placement was off-chain: adjusted height = reveal block height − (2^(level mod 8) − 1) × 4096, and coordinates were assigned from that ordering, so levelling up could move lands when positions were recalculated. **Decided for V2: positions are frozen at the snapshot; new reveals fill sea plots in a fixed spiral from Orthohenge.**
- Also included: tile configs for both realms (`config/tiles-fantasy.js`, `config/tiles-futuristic.js`), land name generator (`config/names.cjs`), heraldry (escutcheons, ordinaries, coronets), and the map scripts.
- Security review: no private keys, mnemonics, `.env` files or RPC/API keys. Only local dev default passwords (Postgres `orthoverse`/`orthoverse`, pgAdmin `admin`). Personal data limited to wallet addresses linked to lands, which is public chain data. `toolchain.sh` links a Google Drive `bigmap.zip` shared by link.

## World geometry

- A land is 6 × 6 chunks = 96 × 96 blocks. Land coordinate = floor(block / 96); key `"landX:landZ"`.
- Playable map is lands −56..56 (113 × 113 lands, about 10,850 blocks across). Ring 57 is grass plains with mountain edges; ring 58 is a bedrock wall. Unrevealed land inside is sea.
- Base ground level around y = 43 (`80 - 15 - 30 + 8`).
- Nine henges in `special.json`: Orthohenge at 0:0, and Luoden-, Pohjan-, Koillisen-, Lännen-, Idän-, Lounaan-, Etelän- and Kaakkonhenge at the ±30 compass points. Each has its own 36-tile feature string.

## How a land is generated

- Each of the 36 chunk tiles gets one feature from one hex digit of the **token ID** (characters 2 to 37). The token ID is fixed at reveal (derived from the revealing address) and never changes on sale, so a land's terrain never depends on its current owner.
- Level 0 to 7 is the natural realm; 8 to 15 is the "flipped" realm (`level > 7`), with its own tile set.
- Natural realm tiles: 0 lush hill, 1 lush mountain, 2/a lake, 3 plains, 4/c/f deciduous wood, 5 lush plains, 6 quarry, 7 evergreen, 8 barren hill, 9 barren mountain, b desert, d badlands, e cobble quarry.
- Flipped realm tiles (on tarmac): 0/8 cube, 1/9 pyramid, 2/a slime lake, 3/b square, 4/c dome, 5/d speckle, 6/e pit, 7/f prism.
- Castle: level mod 8 picks one of castle_1..7 (natural) or castle_9..15 (flipped, with rockets at the top levels). It takes the 2 × 2 tiles at positions (2..3, 2..3) natural, (2..3, 4..5) flipped. Builders are in `orthogen/special.js` (~1,750 lines).
- Generation is deterministic from (token ID, level, seed 100).

## Ownership and editing (old)

- Digging and placing allowed only if the player's verified wallet ("cape confirmed") is among the land's owners.
- Owners could save and load their land edits in numbered slots (bitmap JSON per land), with a cooldown of 11 minutes minus one minute per level.
- Level or realm changes regenerated the land and dropped the save slot.

## Snapshot in orthoverse-prismarine (`map-data/owners.json`)

- 1,927 lands, 1,881 owner addresses, land coordinates −37..37 (a slightly later snapshot than the SQLite dump). Each entry: [name, token ID, level, x, z], grouped by owner address.
- Levels: 1,540 at 0; 158 at 1; 60 at 2; 23 at 3; 13 at 4; 6 at 5; 8 at 7; 38 at 8; 36 at 9; 25 at 10; 12 at 11; 5 at 12; 2 at 13; 1 at 15.

## Implications for the Luanti version

- Self-contained data: positions, names and crests from the snapshot; current owners and levels from the chain via an indexer reading the mainnet contract. No dependency on any old service.
- A land has three independent properties: token ID (terrain, permanent), position (frozen), level (castle and realm, changes).
- A 96-block land is exactly 6 Luanti mapblocks. Setting the mapgen `chunksize` to 6 would make each Luanti mapchunk one Orthoverse land horizontally. To verify.
- The whole map fits easily inside Luanti's ±31,000 world limit.
- The generator ports cleanly to a Lua mapgen (VoxelManip), tile by tile, with castles as schematics.
- Parcel lookup for the ownership check is floor(x / 96), floor(z / 96).
- The browser client is lost: Luanti needs an installed client (desktop or Android).
- orthoverse.land can host the wallet-binding page, the map, and the game's remote media.
