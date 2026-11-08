# Adventures as built (8 Nov 2026)

What exists on the adventure branch today (patches 1007 to 1017). The plans behind it are in [dungeons-plan.md](dungeons-plan.md), [adventure-runs.md](adventure-runs.md) and [adventure-decisions.md](adventure-decisions.md). The code is in `mods/orthoverse_adventure/init.lua`; the website side is `web/site/adventures/` and `/api/adventures` in `web/auth/server.js`.

This is milestone 1 from the decisions: adventure mode, the gate, the finish, Mesecons, one party at a time with a restore after each run, and a completions list. No monsters, levels, kit, lockout or parties yet.

## For players

- An adventure has an **entrance** (the arrival point) outside its dungeon. Players gather there and right-click the **Adventure gate**, which shows the adventure's name, its line, its records and an Enter button.
- Entering takes the player to the **start**, inside the dungeon. The first player through starts a **run**; others may join through the gate for a minute after that (up to 6). Then the gate is shut until the run ends.
- Touching the **Adventure finish** (right-click or punch) completes it. Everyone in the run has two minutes to look around, then is brought back to the entrance.
- A run also ends at the time limit (30 to 120 minutes, set by the builder, 60 at first), or when everyone has left it: by walking out of the area, dying, or being away from the game for more than five minutes.
- After every run the dungeon is put back exactly as it was saved ("restocking", a few seconds) before the next party can go in.
- While an adventure is open, nobody but the run's players may be inside the dungeon area: anyone else is put back at the entrance. Nobody has creative mode inside it, the holder included.
- Completions are recorded for signed-in characters (wallet or password). Runs by the builder, the admin and guests are not recorded, and the game says so at the finish. The first completion of each version is announced to everyone in the game.
- `/adventure leave` gives up a run and takes you back to the entrance (any player; the game says so on entering).
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

### Ready-made adventures

The admin can place a finished building from the game's `adventures/` folder with `/adventure place <name>`, standing on the ground at its south-west corner. It clears the footprint, builds the adventure and sets its area, start, arrival, name and line, leaving it closed for the builder to finish, save and open. The first is The Three Bells: see [adventures/README.md](../adventures/README.md), and [tools/adventures/README.md](../tools/adventures/README.md) for how it is generated.

A **pile of pebbles** (from the Creative tab) gives a pebble when punched: something to throw, for puzzles with a pressure plate out of reach. Pebbles do nothing else.

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

## Combat experiment (milestone 2, patch 1021)

`mods/orthoverse_combat` tries the hold-and-release fighting from [combat-numbers.md](combat-numbers.md) before any monsters exist. Seven weapons (dagger, short sword, broadsword, spear, mace, morning star, war hammer), each in steel, bronze, mese and diamond (the damage rising in that order), and a training dummy are in the Creative tab. Hold the attack button to wind up; nothing on the screen shows the sweet spot: players learn each weapon's timing by feel. In the browser game a client patch (web/client/patches/luanti-hold-attack.patch) stops the swinging, digging and punching while the button is held with one of these weapons: the weapon in the hand rises (slashing and bashing weapons), is levelled (the dagger) or is pointed at the target (the spear) as the blow gathers strength, sags and trembles when the arm tires, and swings once on release (the spear jabs forward). It reads the weapon's timing from item groups (hold_attack, hold_tires, hold_thrust, hold_jab). Other Luanti clients swing the weapon over and over while the button is down, with no sign of the timing at all. Each weapon in the hand has a fist on its grip. Release to strike. The blow is traced from the eye: distance against the weapon's best range and reach, height on the target (head, body, legs) and side (front, side, behind) count, with hidden SRD-style rolls. The dummy shows each blow over its head, and the chat shows the numbers behind it, for tuning. Right-click the dummy to change its armour; sneak and punch it to remove it. The weapons dig nothing. Nothing else a player holds does any harm: fists, tools and blocks do no damage to animals, monsters or players.

Measured through the native client: a hold is timed to within about 0.05 to 0.1 s of the real one, enough for the sweet spot to be hit on purpose.

## Monsters (patch 1022)

Mobs Redo (mods/mobs) runs them; `mods/orthoverse_monsters` defines them: kobold, goblin, orc and skeleton (new skins on the character model, painted by `tools/monsters/make_monster_skins.py`), and mossling, hexer and wisp from esp32-s3-minetest. Goblins carry spears, kobolds daggers, orcs morning stars, skeletons bronze short swords (pictures without the human fist).

- None spawn in the world. A builder places **Monster spawners** (Creative tab, a grate in the floor), and right-clicks one to choose the monster, how many (1 to 6) and how near a player must come (4 to 24 blocks). A spawner wakes once per run, when a player of the run comes near. While the adventure is closed it brings nothing by itself: its **Bring now** button tries it.
- A monster that leaves its adventure's dungeon area, or outlives its run, is removed; the restore after each run removes them all.
- Only hold-and-release blows hurt them. They wind up before they strike (the punch animation and a swing sound): step back out of reach and the blow misses. A head hit at full strength stuns them for a second; a mace, morning star or war hammer knocks them back further.
- Hexers keep their distance and lob slow orbs; wisps drift close, swell and burst (breaking nothing on a land).
- They drop nothing, break nothing (mobs_griefing off), and show no health on hover.
- `/monster <kind>` (server privilege) brings one in front of the admin, anywhere, to look at or fight.
- Mobs Redo's "peaceful player" privilege, which would make monsters ignore a player, is given to nobody (the admin would otherwise have it).
