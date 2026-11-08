# Adventures as built (9 Nov 2026)

What exists on the adventure branch today (patches 1007 to 1036). The plans behind it are in [dungeons-plan.md](dungeons-plan.md), [adventure-runs.md](adventure-runs.md) and [adventure-decisions.md](adventure-decisions.md). The code is in `mods/orthoverse_adventure/init.lua`; the website side is `web/site/adventures/` and `/api/adventures` in `web/auth/server.js`.

Milestone 1 (adventure mode, the gate, the finish, Mesecons, one party at a time with a restore after each run, a completions list) and most of milestone 2 (combat, monsters, rank and experience, loot, the death lockout, entry ranks, The Gullet). Not yet: parties, the downed and ghost rules, checkpoints, private copies.

## For players

- An adventure has an **entrance** (the arrival point) outside its dungeon. Players gather there and right-click the **Adventure gate**, which shows the adventure's name, its line, its records and an Enter button.
- Entering takes the player to the **start**, inside the dungeon. The first player through starts a **run**; others may join through the gate for a minute after that (up to 6). Then the gate is shut until the run ends.
- Touching the **Adventure finish** (right-click or punch) completes it. Everyone in the run has two minutes to look around, then is brought back to the entrance.
- A run also ends at the time limit (30 to 120 minutes, set by the builder, 60 at first), or when everyone has left it: by walking out of the area, dying, or being away from the game for more than five minutes.
- Each adventure is for a range of character ranks (1 to 5 at first; the gate shows it). Only players within it may go in; the builder and the admin always may.
- Dying in a run ends it for that player, who comes back to life at the entrance having lost nothing (their inventory is kept, not left in bones), but may not go back in for 10 minutes; each further death there within 4 hours doubles it, to an hour at most, and it all clears the next day.
- Anyone who goes in without a weapon is given a steel short sword at the gate.
- After every run the dungeon is put back exactly as it was saved ("restocking", a few seconds) before the next party can go in.
- While an adventure is open, nobody but the run's players may be inside the dungeon area: anyone else is put back at the entrance. Nobody has creative mode inside it, the holder included.
- Completions are recorded for signed-in characters (wallet or password). Runs by the builder, the admin and guests are not recorded, and the game says so at the finish. The first completion of each version is announced to everyone in the game.
- `/adventure leave` gives up a run and takes you back to the entrance (any player; the game says so on entering).
- An **Adventure board** at the entrance shows the records; so does the website's Adventures page (`/adventures/`, linked from every page's header and footer).

## For builders

On a land at castle level 5 or more (the admin anywhere). `/adventure` with no arguments opens the same steps in a window.

1. `/adventure create <name>`: make an adventure on the land you stand on.
2. `/adventure line <text>`: a one-line description for the gate and the website.
   `/adventure ranks <lowest> <highest>`: who may go in, by character rank (1 to 5 at first). Its loot chests give metals up to the highest.
3. `/adventure corner1` at one corner of the dungeon, `/adventure corner2` at the opposite corner (higher or lower too). The dungeon is the box between them, within the land.
4. `/adventure start` where players appear when they go in, inside the dungeon.
5. `/adventure arrival` at the entrance, outside the dungeon, where players gather and come back to.
6. From the Creative tab, place an Adventure gate at the entrance and an Adventure finish at the end of the dungeon; an Adventure board at the entrance if wanted.
7. Build the dungeon. `/adventure save` takes a snapshot: after every run the dungeon returns to exactly this. Each save is a new version with fresh records.
8. `/adventure open`. While closed, only the builder can be inside.

Other commands: `limit <minutes>`, `name <text>`, `close`, `reset`, `status`, `delete` (records and saved dungeons are kept). Start and arrival can be set again at any time; the corners while closed, then save.

To test a record, play it with another character: the builder's own runs are not recorded.

### Ready-made adventures

The admin can place a finished building from the game's `adventures/` folder with `/adventure place <name>`, standing on the ground at its south-west corner. It clears the footprint, builds the adventure and sets its area, start, arrival, name and line, leaving it closed for the builder to finish, save and open. There are two: The Three Bells (puzzles, every rank) and The Gullet (a ravine of monster caves below a fort, with an orc warlord, ranks 1 to 5): see [adventures/README.md](../adventures/README.md), and [tools/adventures/README.md](../tools/adventures/README.md) for how it is generated.

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

Our party module (the share of experience already counts everyone in a run), the downed and ghost rules, checkpoints, hired companions, private copies, shuffles on reset, level-gated doors, the builder's test mode, adventures across several lands, completions on the token card, rank on the website, armour. The adventurer's kit (a separate inventory) was dropped: weapons are ordinary items, made or found, and a metal counts in full only from a rank, so gear cannot be handed out unfairly; loot chests fill from our own tables, never from a builder's creative inventory.

## Combat experiment (milestone 2, patch 1021)

`mods/orthoverse_combat` tries the hold-and-release fighting from [combat-numbers.md](combat-numbers.md) before any monsters exist. Seven weapons (dagger, short sword, broadsword, spear, mace, morning star, war hammer), each in steel, bronze, mese and diamond (the damage rising in that order), and a training dummy are in the Creative tab. Hold the attack button to wind up; nothing on the screen shows the sweet spot: players learn each weapon's timing by feel. In the browser game a client patch (web/client/patches/luanti-hold-attack.patch) stops the swinging, digging and punching while the button is held with one of these weapons: the weapon in the hand rises (slashing and bashing weapons), is levelled (the dagger) or is pointed at the target (the spear) as the blow gathers strength, sags and trembles when the arm tires, and swings once on release (the spear is driven straight forward and drawn back). It reads the weapon's timing from item groups (hold_attack, hold_tires, hold_thrust, hold_jab). Other Luanti clients swing the weapon over and over while the button is down, with no sign of the timing at all. Release to strike. The blow is traced from the eye: distance against the weapon's best range and reach, height on the target (head, body, legs) and side (front, side, behind) count; a blow that connects always lands (armour takes some damage off), and a blow within 20 degrees of a monster finds it. Its sound tells how good it was. The dummy shows each blow over its head, and the chat shows the numbers behind it, for tuning. Right-click the dummy to change its armour; sneak and punch it to remove it. The weapons dig nothing. Nothing else a player holds does any harm: fists, tools and blocks do no damage to animals, monsters or players.

Measured through the native client: a hold is timed to within about 0.05 to 0.1 s of the real one, enough for the sweet spot to be hit on purpose.

## Monsters (patch 1022)

Mobs Redo (mods/mobs) runs them; `mods/orthoverse_monsters` defines them: kobold, goblin, orc and skeleton (new skins on the character model, painted by `tools/monsters/make_monster_skins.py`), and mossling, hexer and wisp from esp32-s3-minetest. Goblins carry spears, kobolds daggers, orcs morning stars, skeletons bronze short swords.

- None spawn in the world. A builder places **Monster spawners** (Creative tab, a grate in the floor), and right-clicks one to choose the monster, how many (1 to 6) and how near a player must come (4 to 24 blocks). A spawner wakes once per run, when a player of the run comes near. While the adventure is closed it brings nothing by itself: its **Bring now** button tries it.
- A monster that leaves its adventure's dungeon area, or outlives its run, is removed; the restore after each run removes them all.
- Only hold-and-release blows hurt them. They wind up before they strike (the punch animation and a swing sound): step back out of reach and the blow misses. A head hit at full strength stuns them for a second; a mace, morning star or war hammer knocks them back further.
- Each kind has a level and an experience value: kobold and mossling level 1 (25), goblin 2 (50), skeleton and wisp 3 (75), orc 4 (100), hexer 4 (120), the orc warlord 5 (300, the boss of The Gullet: a crowned great orc with 70 health).
- A monster turns to a player who comes clearly nearer, or who strikes it from no further away than its target.
- Hexers keep their distance and lob slow orbs. One that a player stays close to shimmers for a moment, then blinks away (at most every 8 s): the shimmer is the moment to strike. A blow staggers a hexer for half a second, so it cannot cast or blink.
- Wisps float a man's height above the ground, come down to chest height to go for a player, swell and burst like a small TNT blast: up to 8 hearts at a block away, less further out, with a push. A burst breaks nothing.
- They drop nothing, break nothing (mobs_griefing off), and show no health on hover.
- `/monster <kind>` (server privilege) brings one in front of the admin, anywhere, to look at or fight.
- Mobs Redo's "peaceful player" privilege, which would make monsters ignore a player, is given to nobody (the admin would otherwise have it).

## Rank and experience (patch 1034)

`mods/orthoverse_rank`: a character's rank, 1 to 20, from experience (300 for rank 2, 900 for 3, 2,700 for 4, 6,500 for 5, up to 355,000 for 20). It is shown at the bottom right; `/rank` gives the details, and the admin can look at or set anyone's (`/rank <player> <rank>` or `+<xp>`). Rank is never lost.

- **What rank gives:** health (20 at rank 1, +2 a rank, shown as the same 10 hearts), a wider sweet spot (0.25 s at rank 1 to 0.45 s at 20), +1 damage every four ranks, and the full strength of better metals: steel from rank 1, bronze 3, mese 6, diamond 10. Below that a weapon gives the bonus of the best metal the rank allows; its description says "Full strength from rank N".
- **Experience from monsters:** shared by the run's players within 32 blocks (10% more for each extra member), scaled by the monster's level against each player's rank: 5 or more below, nothing; 2 to 4 below, half; even, full; 2 to 4 above, one and a half; 5 or more above, double.
- **Against farming:** nothing for a monster that was not really fighting (it must have struck at someone, cast, lit its fuse, or been close to its target and able to see them in the last 15 s); a spawner's monsters on another run the same day give a quarter less each time; at most 1,500 a day from one adventure's monsters; nothing for guests, or for the builder and the admin in their own adventure.
- **Finishing** an adventure gives 200, once a day for each player whose run counts.

## Loot (patch 1035)

`mods/orthoverse_loot`:
- **Loot chests** (Creative tab): the builder right-clicks one to choose what it gives. Common: a healing draught or two, now and then a weapon. Weapon: a weapon and a draught. Finish: the best metal the adventure allows, once a day for each player. In a run, everyone who opens a chest finds their own share. What a chest gives is capped by the adventure's top rank (bronze at most for ranks up to 5, mese from 6, diamond from 10), the lower metals more often.
- **Healing draughts:** 8 health, found only in chests.
- **Weapon recipes** for every kind in every metal (steel or bronze ingots, mese crystals, diamonds, and sticks): dagger m/s; short sword m/m/s; broadsword with a crossguard; spear diagonal; mace, morning star and war hammer each their own shape (none clashes with Minetest Game's tools; the craft guide shows them).
