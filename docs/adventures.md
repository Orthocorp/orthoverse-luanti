# Adventures as built (8 Nov 2026)

What exists on the adventure branch today (patches 1007 to 1012). The plans behind it are in [dungeons-plan.md](dungeons-plan.md), [adventure-runs.md](adventure-runs.md) and [adventure-decisions.md](adventure-decisions.md). The code is in `mods/orthoverse_adventure/init.lua`; the website side is `web/site/adventures/` and `/api/adventures` in `web/auth/server.js`.

This is milestone 1 from the decisions: adventure mode, the gate, the finish, Mesecons, one party at a time with a restore after each run, and a completions list. No monsters, levels, kit, lockout or parties yet.

## For players

- An adventure has an **entrance** (the arrival point) outside its dungeon. Players gather there and right-click the **Adventure gate**, which shows the adventure's name, its line, its records and an Enter button.
- Entering takes the player to the **start**, inside the dungeon. The first player through starts a **run**; others may join through the gate for a minute after that (up to 6). Then the gate is shut until the run ends.
- Touching the **Adventure finish** (right-click or punch) completes it. Everyone in the run has two minutes to look around, then is brought back to the entrance.
- A run also ends at the time limit (30 to 120 minutes, set by the builder, 60 at first), or when everyone has left it: by walking out of the area, dying, or being away from the game for more than five minutes.
- After every run the dungeon is put back exactly as it was saved ("restocking", a few seconds) before the next party can go in.
- While an adventure is open, nobody but the run's players may be inside the dungeon area: anyone else is put back at the entrance. Nobody has creative mode inside it, the holder included.
- Completions are recorded for signed-in characters (wallet or password). Runs by the builder, the admin and guests are not recorded, and the game says so at the finish. The first completion of each version is announced to everyone in the game.
- An **Adventure board** at the entrance shows the records; so does the website's Adventures page (`/adventures/`, linked from every page's header and footer).

## For builders

On a land at castle level 5 or more (the admin anywhere). `/adventure` with no arguments opens the same steps in a window.

1. `/adventure create <name>`: make an adventure on the land you stand on.
2. `/adventure line <text>`: a one-line description for the gate and the website.
3. `/adventure corner1` at one corner of the dungeon, `/adventure corner2` at the opposite corner (higher or lower too). The dungeon is the box between them, within the land.
4. `/adventure start` where players appear when they go in, inside the dungeon.
5. `/adventure arrival` at the entrance, outside the dungeon, where players gather and come back to.
6. From the Creative tab, place an Adventure gate at the entrance and an Adventure finish at the end of the dungeon; an Adventure board at the entrance if wanted.
7. Build the dungeon. `/adventure save` takes a snapshot: after every run the dungeon returns to exactly this. Each save is a new version with fresh records.
8. `/adventure open`. While closed, only the builder can be inside.

Other commands: `limit <minutes>`, `name <text>`, `close`, `reset`, `status`, `delete` (records and saved dungeons are kept). Start and arrival can be set again at any time; the corners while closed, then save.

To test a record, play it with another character: the builder's own runs are not recorded.

### Tools for building

- **Creative mode** on your own land from castle level 2, fly from 3, fast from 4, noclip from 5 ([land-abilities.md](land-abilities.md)).
- **Mesecons**, the dungeon set: wires, insulated and extra wires, receiver, button, wall lever, switch, pressure plates, detector, delayer, torch, lamp, lightstone, noteblock, pistons, movestones, sticky blocks, random. No programmable controllers, logic gates or command block. Pistons and movestones respect land protection (`mesecon.mvps_protection_mode = normal`).
- **WorldEdit** for the admin only (the worldedit privilege). Holders get a land-limited version later.

## What is stored where

- Definitions: the mod's storage (`adv:<land key>`).
- Saved dungeons: `<world>/orthoverse_adventures/<land key>-v<version>.dat` (zstd-compressed nodes, metadata, inventories and timers), covered by the nightly backup.
- Records: mod storage, and `<world>/orthoverse_adventures/adventures.json` for the website.
- If the server stops while a dungeon is in use, the dungeon is restored when it starts again.

## Not built yet (from the decisions)

Monsters and combat, character rank, the adventurer's kit and loot chests, the death lockout, entry level ranges, our party module, checkpoints, hired companions, private copies, shuffles, the builder's test mode, adventures across several lands, completions on the token card.
