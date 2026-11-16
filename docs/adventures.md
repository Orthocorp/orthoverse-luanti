# Adventures as built (9 Nov 2026)

What exists on the adventure branch today (patches 1007 to 1036). The plans behind it are in [dungeons-plan.md](dungeons-plan.md), [adventure-runs.md](adventure-runs.md) and [adventure-decisions.md](adventure-decisions.md). The code is in `mods/orthoverse_adventure/init.lua`; the website side is `web/site/adventures/` and `/api/adventures` in `web/auth/server.js`.

Milestone 1 (adventure mode, the gate, the finish, Mesecons, one party at a time with a restore after each run, a completions list) and most of milestone 2 (combat, monsters, rank and experience, loot, the death lockout, entry ranks, The Gullet). Not yet: parties, the downed and ghost rules, checkpoints, private copies.

## For players

- An adventure has an **entrance** (the arrival point) outside its dungeon. Players gather there and right-click the **Adventure gate**, which shows the adventure's name, its line, its records and an Enter button.
- Entering takes the player to the **start**, inside the dungeon. The first player through starts a **run**; others may join through the gate for a minute after that (up to 6). Then the gate is shut until the run ends.
- Touching the **Adventure finish** (right-click or punch) completes it. Everyone in the run has two minutes to look around, then is brought back to the entrance.
- A run also ends at the time limit (30 to 120 minutes, set by the builder, 60 at first), or when everyone has left it: by walking out of the area, dying, or being away from the game for more than five minutes.
- Each adventure is for a range of character ranks (1 to 5 at first; the gate shows it). Only players within it may go in; the builder and the admin always may.
- **The adventurer's kit.** At the gate the player's own inventory (and crafting grid) is put aside, and they are given the adventure's kit: a steel short sword and a healing draught, unless a ready-made adventure's JSON names its own (`"kit": ["item 1", ...]`). Whatever else they need they find inside.
- Coming out by any way (the finish, the time limit, `/adventure leave`, walking out, dying, or being away too long), what they carried inside stays inside and their own inventory is given back. Things dropped inside are cleared at the end of the run.
- **Treasure.** Gold and gems from loot chests (gold lumps and ingots, mese crystals, diamonds) are marked as treasure (the tooltip says so). A party that reaches the finish takes its treasure out, unmarked, as ordinary items, as far as each player's own inventory has room: what does not fit stays behind. A run that fails takes none. Nothing else found inside comes out: weapons, draughts and torches stay.
- **Torches.** Loot chests sometimes hold torches. A player in a run may place them in the air of the dungeon and take them down again, though nothing else may be built or dug there; the dungeon is put back as saved after the run.
- Dying in a run ends it for that player, who comes back to life at the entrance with their own things (they were with the gatekeeper, so nothing goes into bones), but may not go back in for 10 minutes; each further death there within 4 hours doubles it, to an hour at most, and it all clears the next day.
- A player who was away when their run ended gets their things back on joining again.
- After every run the dungeon is put back exactly as it was saved ("restocking", a few seconds) before the next party can go in.
- While an adventure is open, nobody but the run's players may be inside the dungeon area: anyone else is put back at the entrance. Nobody has creative mode inside it, the holder included.
- Completions are recorded for signed-in characters (wallet or password). Runs by the builder, the admin and guests are not recorded, and the game says so at the finish. The first completion of each version is announced to everyone in the game.
- `/adventure go <name>` takes any player to an open adventure's entrance (its arrival point, outside the gate, facing in), wherever they are; on its own it lists the open adventures and their ranks. Not during a run, and once every 30 seconds (the admin any time). Case and punctuation don't matter (`/adventure go st morwens`). The Adventures page shows each adventure's land token picture beside its description (the map's card of the land, or the classic picture; a click opens the token on OpenSea; /api/adventures gives each adventure's `image` and `token`), the command on each open adventure's card, its ranks, and a **Play this adventure** button: it opens the browser game (`/play/?adventure=<land key>`), and a signed-in character arrives at the adventure's entrance on joining (the auth service records the choice in visits.json for 10 minutes, for any character, only if the adventure is open; the game checks again). Guests are told to type the command instead, as the website cannot vouch for a guest's name. Nobody is sent to an arrival point that is not safe: solid ground under it, room to stand, and nothing that burns (lava, fire) within two blocks. `/adventure arrival` and `/adventure open` refuse an unsafe one, and if it becomes unsafe later (a pit dug, lava poured), players are not moved, told why, and the builder is told too (and the server log says so).
- `/adventure leave` gives up a run and takes you back to the entrance (any player; the game says so on entering).
- An **Adventure board** at the entrance shows the records; so does the website's Adventures page (`/adventures/`, linked from every page's header and footer).

## For builders

On a land at castle level 5 or more (the admin anywhere). `/adventure` with no arguments opens the same steps in a window.

1. `/adventure create <name>`: make an adventure on the land you stand on.
2. `/adventure line <text>`: a one-line description for the gate and the website.
   `/adventure ranks <lowest> <highest>`: who may go in, by character rank (1 to 5 at first). Its loot chests give metals up to the highest.
   `/adventure tags <tag> ...`: up to three tags, shown in coloured boxes beside Open or Closed on the Adventures page: combat, puzzle, skill (jumping, climbing, timing), explore, mystery, spooky, sci-fi, solo (or `none`). A ready-made adventure brings its own (`"tags"` in its JSON). The tags puzzle, skill and combat also raise a character's Insight, Agility and Prowess by one, the first time they complete that adventure (recorded completions only); the Account page shows them on the character sheet.
3. `/adventure corner1` at one corner of the dungeon, `/adventure corner2` at the opposite corner (higher or lower too). The dungeon is the box between them, within the land.
4. `/adventure start` where players appear when they go in, inside the dungeon.
5. `/adventure arrival` at the entrance, outside the dungeon, where players gather and come back to.
6. From the Creative tab, place an Adventure gate at the entrance and an Adventure finish at the end of the dungeon; an Adventure board at the entrance if wanted.
7. Build the dungeon. `/adventure save` takes a snapshot: after every run the dungeon returns to exactly this. Each save is a new version with fresh records.
8. `/adventure open`. While closed, only the builder can be inside.

Other commands: `limit <minutes>`, `name <text>`, `close`, `reset`, `status`, `delete` (records and saved dungeons are kept). Start and arrival can be set again at any time; the corners while closed, then save.

To test a record, play it with another character: the builder's own runs are not recorded.

### Ready-made adventures

The admin can place a finished building from the game's `adventures/` folder with `/adventure place <name>`, standing anywhere on the land: it is built in the middle of the land, on the land's ground (`here` builds it with its south-west corner where the admin stands instead); `/adventure place <name> north` turns it round, so its entrance (the gate and anything outside it, such as The Gullet's village) is at the north end, the footprint the same. A ready-made adventure's ground takes the land's own, as the map makes it: tarmac over stone on a land of the flipped (futuristic) realm, castle level 8 and up; grass over dirt elsewhere. To undo a placement, `/adventure close` and `/adventure delete` on the land, then `/remakeland <land> confirm` (admin) makes the land again from scratch as the map first made it, losing everything built on it. It clears the footprint, builds the adventure and sets its area, start, arrival, name and line, leaving it closed for the builder to finish, save and open. Only the admin may place one, and may place it on any land, a croft included. Nobody but an adventure's builders (and the admin) digs or builds inside its area, nor anywhere a ready-made adventure placed blocks (its village outside too), and its ground counts as built on, so a castle upgrade or a flip keeps it. There are eleven: The Three Bells (puzzles, every rank), The Gullet (a gorge of monster caves below a fort, with an orc warlord, ranks 1 to 5), The Fallen Star (a buried starship: keycards, a live floor, robots and the Warden, ranks 3 to 7), The Mill at Withy Ford (a haunted mill, smugglers, an underground river and the Ringmaster, ranks 1 to 5) St Morwen's (a haunted church and churchyard, its bell, its crypt and the wight, ranks 4 to 8), The Wyrm Below, Tir Na Nog and The Seed (a living growth walled in round a survey camp: the hangar's crane, the Gut, the Lung, the Nest and the Heart, ranks 5 to 10) Death at the Château (a murder mystery for one, drawn anew each run, every rank) Eight Queens (a queens puzzle for one on the Queen's floor, drawn anew each run, every rank) and the Tomb of Tahna (a mummy queen's tomb under the desert, three levels deep, ranks 8 to 15): see [adventures/README.md](../adventures/README.md), and [tools/adventures/README.md](../tools/adventures/README.md) for how it is generated.

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

Our party module (the share of experience already counts everyone in a run), the downed and ghost rules, checkpoints, hired companions, private copies, shuffles on reset, level-gated doors, the builder's test mode, adventures across several lands, completions on the token card, rank on the website, armour. Loot chests fill from our own tables, never from a builder's creative inventory, and a metal counts in full only from a rank, so gear cannot be handed out unfairly.

## Combat experiment (milestone 2, patch 1021)

`mods/orthoverse_combat` tries the hold-and-release fighting from [combat-numbers.md](combat-numbers.md) before any monsters exist. Seven weapons (dagger, short sword, broadsword, spear, mace, morning star, war hammer), each in steel, bronze, mese and diamond (the damage rising in that order), and a training dummy are in the Creative tab. Hold the attack button to wind up; nothing on the screen shows the sweet spot: players learn each weapon's timing by feel. In the browser game a client patch (web/client/patches/luanti-hold-attack.patch) stops the swinging, digging and punching while the button is held with one of these weapons: the weapon in the hand rises (slashing and bashing weapons), is levelled (the dagger) or is pointed at the target (the spear) as the blow gathers strength, sags and trembles when the arm tires, and swings once on release (the spear is driven straight forward and drawn back). It reads the weapon's timing from item groups (hold_attack, hold_tires, hold_thrust, hold_jab). Other Luanti clients swing the weapon over and over while the button is down, with no sign of the timing at all. Release to strike. The blow is traced from the eye: distance against the weapon's best range and reach, height on the target (head, body, legs) and side (front, side, behind) count; a blow that connects always lands (armour takes some damage off), and a blow within 20 degrees of a monster finds it. Its sound tells how good it was. The dummy shows each blow over its head, and the chat shows the numbers behind it, for tuning. Right-click the dummy to change its armour; sneak and punch it to remove it. The weapons dig nothing. Nothing else a player holds does any harm: fists, tools and blocks do no damage to animals, monsters or players.

Measured through the native client: a hold is timed to within about 0.05 to 0.1 s of the real one, enough for the sweet spot to be hit on purpose.

## Monsters (patch 1022)

Mobs Redo (mods/mobs) runs them; `mods/orthoverse_monsters` defines them: kobold, goblin, orc and skeleton (new skins on the character model, painted by `tools/monsters/make_monster_skins.py`), and mossling, hexer and wisp from esp32-s3-minetest. Goblins carry spears, kobolds daggers, orcs morning stars, skeletons bronze short swords. The Fallen Star's robots: scrap drones (floating, they ram), security robots (stun batons), sentry turrets (fixed; they fire bolts) and the Warden (its boss), painted by `tools/scifi/make_textures.py`.

- None spawn in the world. A builder places **Monster spawners** (Creative tab, a grate in the floor), and right-clicks one to choose the monster, how many (1 to 6) and how near a player must come (4 to 24 blocks). A spawner wakes once per run, when a player of the run comes near. While the adventure is closed it brings nothing by itself: its **Bring now** button tries it. Two settings a generator script can give a spawner in its metadata: `at`, an offset such as `(6,0,-3)`, brings its monsters round that spot instead of round the spawner (so a spawner by a room's corner, woken from the passage outside, fills the room before anyone comes in); `per_player`, such as `0.5`, brings that many times as many again for each player in the run after the first, rounded up (the Tomb of Tahna's spawners have both).
- A monster that leaves its adventure's dungeon area, or outlives its run, is removed; the restore after each run removes them all.
- Only hold-and-release blows hurt them. They wind up before they strike (the punch animation and a swing sound): step back out of reach and the blow misses. A head hit at full strength stuns them for a second; a mace, morning star or war hammer knocks them back further.
- Each kind has a level and an experience value: kobold and mossling level 1 (25), goblin 2 (50), skeleton and wisp 3 (75), orc 4 (100), hexer 4 (120), the orc warlord 5 (300, the boss of The Gullet: a crowned great orc with 70 health). Drone 3 (60), security robot 5 (110), turret 5 (90), the Warden 7 (400, 100 health). The Mill's: the masked kobold 1 (30: a kobold in a painted skull mask, a skeleton until struck) and the Ringmaster 5 (300, a hexer in a red coat with 45 health). St Morwen's undead: the zombie 4 (90: slow, 30 health; its blow grabs, and for 0.8 s you can hardly move), the ghoul 5 (110: quick; one blow in three numbs, half speed for 2 s) and the wight 8 (500, 90 health: its blows heal it, and at half health it calls up two skeletons).
- A monster turns to a player who comes clearly nearer, or who strikes it from no further away than its target.
- Hexers keep their distance and lob slow orbs. One that a player stays close to shimmers for a moment, then blinks away (at most every 8 s): the shimmer is the moment to strike. A blow staggers a hexer for half a second, so it cannot cast or blink.
- Wisps float a man's height above the ground, come down to chest height to go for a player, swell and burst like a small TNT blast: up to 8 hearts at a block away, less further out, with a push. A burst breaks nothing.
- They drop nothing, break nothing (mobs_griefing off), and show no health on hover.
- **The undead** (skeletons, zombies, ghouls, the wight) cannot set foot on consecrated floor, a church's great bell stuns them, and a fighter blessed with holy water (from a font) does 3 more with every blow that lands on them.
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
- **Loot chests** (Creative tab): the builder right-clicks one to choose what it gives. Common: a healing draught or two; often gold lumps; now and then torches, a weapon, a piece of armour, a draught of swiftness or a mese crystal. Weapon: a weapon and a draught; sometimes gold ingots or torches. Armour: a piece of armour (a helmet, chestplate, leggings, boots or a shield) and a draught; sometimes gold ingots. Finish: the best metal the adventure allows, two draughts, a draught of swiftness, gold ingots and a gem (mese, or now and then a diamond), once a day for each player. In a run, everyone who opens a chest finds their own share. What a chest gives is capped by the adventure's top rank (bronze at most for ranks up to 5, mese from 6, diamond from 10; armour: wood, then gold and bronze from rank 3, steel from 6, diamond from 10, from the best three allowed), the lower metals more often. Weapons and armour found inside stay inside.
- **Healing draughts:** 8 health, found only in chests.
- **Draughts of swiftness:** half as fast again on foot for a minute (drinking another starts the minute again), found only in chests.
- **Footwork:** with a weapon in hand, walking backwards is slower than walking (0.6 times, slower than any monster runs), and walking backwards while winding up a blow is as slow as sneaking. So a fighter cannot keep backing out of a monster's reach and then dart in to strike. Forward and sideways are as ever.
- **Weapon recipes** for every kind in every metal (steel or bronze ingots, mese crystals, diamonds, and sticks): dagger m/s; short sword m/m/s; broadsword with a crossguard; spear diagonal; mace, morning star and war hammer each their own shape (none clashes with Minetest Game's tools; the craft guide shows them).

## The ship's blocks (mods/orthoverse_scifi)

For The Fallen Star and for any builder's adventure, all in the Creative tab: hull plating (plain, scorched), deck grating, panel lights, ship's glass, cargo crates, consoles, reactor cores, and:
- a **loose panel**: looks like hull plating, but players walk through it;
- **keycards** (blue, red) and **card doors**, which open for a player in a run carrying the card (every block of the door at once), or for the builder; **card lockers**: of all the lockers of one colour in an adventure, one, chosen at random at the first opening of each run, holds that card (a builder right-clicks a locker to change its colour);
- **relays** and **blast doors**: when every relay in the adventure is thrown, its blast doors open and its live floors go dead;
- **deck plates** in two sets (A and B) and a **live floor controller** that runs every plate within 32 blocks of it (hide it in a wall);
- a **medical station** (a full heal, once per player per run) and the **black box** (an adventure finish in the ship's look);
- and in orthoverse_loot, the **loot locker**: a loot chest in steel.

## Fantasy fittings (mods/orthoverse_props)

For The Mill, St Morwen's and any builder's adventure, in the Creative tab:
- a **secret shelf** (looks like a bookshelf) and a **loose brick** (stone brick with a crack): right-clicking the brick slides away every secret shelf within 6 blocks of it;
- **windlasses** and **sluice gates**: when every windlass in the adventure is wound, its sluice gates rise;
- a **mooring post**: set beside water, it keeps a rowing boat there for a run's players (a new one when none is near, up to six a run);
- the **ledger**: an adventure finish, as a book on a desk.
- a **secret wall** (stone brick): a loose brick slides it away as it does secret shelves (St Morwen's hides a stair under a floor of it);
- a **great bell**: rung, it stuns every one of the undead within 32 blocks for 4 seconds (once every 20 seconds), and its first ring in a run opens the adventure's **crypt gates** (iron bars, locked till then);
- a **font**: three flasks of **holy water** a player a run (drunk: for a minute, 3 more with every blow that lands on the undead);
- **consecrated floor**: the undead cannot set foot on it;
- **headstones**, a **wall of bones**, and a **fog emitter** (invisible: low fog drifts round it while players are near);
- the **reliquary**: an adventure finish, as a gold casket.

All of them are put back as saved when the adventure is restored after a run.

## The growth and the survey camp (mods/orthoverse_seed)

For The Seed and any builder's adventure, in the Creative tab:
- the growth: **crust**, **ribbed growth** (two shades), **flesh**, **glowing nodules**; when an adventure's Heart dies, all its growth withers to **ash**;
- **membranes** (fire burns them open) and **valves** (membranes in sets: of all the valves of one set in an adventure, one, chosen at random at the start of each run, stands open; a builder right-clicks one to change its set);
- **acid** (burns, and wears armour as a blow does) and **floating pads** on it, which sink a moment after someone steps on them and come up a few seconds later;
- **egg sacs**, which burst when the spawner beside them wakes (a spawner with `stealth` set wakes for a sneaking player only at half its distance);
- **spore vents** (spores cloud the sight and slow anyone near without a breathing mask) and **gust vents** (hidden in a wall: every 14 seconds the growth breathes in, then out, and the gust pushes players the way the vent faces);
- **creep buds** in a floor: during a run, creep spreads from them over the floor, slowing whoever wades through it (fire burns it);
- **the Heart's shell** (opens when three ganglia are cut) and **core** (opens when the last of its nodules bursts: then the growth withers);
- the camp: **survey stores** (three fire pots and a breathing mask, once per player per run) and a **rifle rack** (a plasma rifle, once per player per run, and its charge renewed);
- **fire pots** (thrown with a left click: flame where they land), the **breathing mask** (carried: spores do no harm while its filters last, about 50 seconds) and the **plasma rifle** (left click: a bolt of plasma, twelve to a charge, one a second; it works only in a run);
- the **crane**: a rail, a trolley under it, a cable and a magnet, **cargo containers**, and five **crane buttons** (left and right as the player at them sees it, up, down, and the magnet on and off) that drive the nearest trolley within 24 blocks. The magnet lifts the containers under it; let go, they fall.

All of them are put back as saved when the adventure is restored after a run.

## The château (mods/orthoverse_chateau)

For Death at the Château and any builder's adventure, in the Creative tab:
- walls and floors: **parquet**, **marble** (white, black, rose), **white and gold panelling**, **mahogany panelling**, **silk damask** (red, blue, green), **carpet**, **flagstones**, **kitchen tiles**, **pale limestone**, **roof slates**, a **painted ceiling** and a **gilded cornice** (which gives a soft light);
- fittings: **mirrors**, the guests' **portraits**, **crystal chandeliers**, **candles**, a **marble fireplace**, tables (a **banquet table**, a **writing desk**, a **billiard table**), **dining chairs**, **armchairs**, a **grand piano** and its bench, a **harp**, **barrels**, **wine racks**, **copper pans**, a **bread oven**, **chests of drawers**, a **long-case clock**, **beds**, **ivy**, **goblets**, **locked doors** (two halves; they never open);
- the six weapons in their places (the **silver candlestick**, the **ivory letter opener**, the **apothecary cabinet** with the belladonna, the **dueling pistols**, the **curtain and its cord**, the **fire irons** with the poker), each also in a form with the weapon gone;
- **guests' chairs** (a chair whose metadata `guest` names a guest: the guest sits in it, a still figure, set back by the chair after every restore) and the **rug** where Monsieur Lenoir lies;
- the mystery's own blocks: **clue places** (drawers, papers, a barrel, a casket, an armchair, the piano bench, a wall safe; metadata `spot`, what the casebook calls it, `room`, the room's id, and `gate`, the puzzle in front of it if any: `closet`, `study`, `piano` or `safe`), the **music stand**, the **menu card**, the **key hook**, the **false volume** and the **shelf door** it opens, the **rack door** (it turns when the menu's vintage is drawn from it), **Madame Or's table**, the **accusation desk** and the **notice** (how to play).

The mystery (`mods/orthoverse_chateau/mystery.lua`) works on an adventure placed from the template `chateau`: at the start of each run it draws the murderer, the weapon, the room and the moment of death, takes the weapon (and one other, taken for an innocent reason) from its place, and fills every clue place in the area: an alibi for each innocent guest (with whoever they were with, and the room, at the moment of death), a note clearing each room nobody was in, the murderer's alibi for the wrong hour, the innocent weapon's story, the murder weapon behind a puzzle, a trace in the room where he died, and motives or nothing in the rest. The puzzles' answers (the vintage, the tune, the year on the Comte's portrait) are drawn each run too. A second wrong accusation fails the player out of the run (`orthoverse.adventure.expel`: no experience, and the lockout as for dying). A ready-made adventure's JSON may limit the party (`"party_max": 1`).

All of it is put back as saved when the adventure is restored after a run.

## The Tomb of Tahna (mods/orthoverse_tahna)

For the Tomb of Tahna and any builder's adventure, in the Creative tab: walls of carved signs, tomb sandstone, gold tiles, scorched stone, floor flags; **paintings** (two blocks by two, five of them) and **tablets** of carved signs (right-click to read; their words are set in their metadata, `text`); **false walls** that look like cobble, mossy cobble, carved signs, tomb sandstone or sandstone and can be walked through; and the traps, each sprung once a run:

* **Falling ceiling:** its plate (a cracked flag) brings every falling-ceiling block within 10 down over the room, a layer every half second, then lifts it again; whoever is still under it when it comes low takes 30.
* **Flame jets:** plates (scorched stone) set the nozzles within 7 roaring for 6 blocks across the hall (30 to whoever is in a jet's path).
* **Darts:** its plate (a cracked flag) sets every dart hole within 8 shooting across the corridor, three volleys (3 a dart, at most 18 to each player).
* **Pit:** its plate drops the false floor round it (within 2) into whatever is below (spikes hurt 5 a second).
* **False door:** touched, it brings spears up through the spear floor within 3 of it (28 to whoever stands on it).
* **Archway:** its mark (invisible) sends whoever walks into it to the nearest **return mark**.
* **The drowning room:** **buttons** in its wall (each pops out again 0.6 s after it is pressed). When as many are in at once as there are living players in the run, the **slab marks** round the room come down as slabs and the room (marked out by its **drowning room floor**, which looks like a flagged floor) fills with water a layer every 1.5 s; whoever has water over their head takes 5 a second as well as drowning. No way out.
* **Endless passage floor** (looks like stone brick, an east end and a west end): whoever treads on it is set back along the passage (24 blocks west from the east end, 8 east from the west end), with no sign.
* **The pyramid's sarcophagus:** opened, it drops the slabs within 14 into their places (the slab marks) and wakes two mummies; a **lever** lifts the slabs again.

Trap damage is set straight on health: armour does not help. Also: three **canopic jars** (struck, they break), a **pedestal**, **Tahna's sarcophagus** (a finish: shut until she is slain in the run, then each player who touches it takes the **Sceptre of Tahna**, once a character ever, as treasure that comes out with them, and completes the adventure), and the sceptre itself, which stands like a torch, for show.

The monsters are in orthoverse_monsters: the **mummy**, **scarabs**, the **tomb guardian**, the **skeleton warrior** (an old soldier of the tomb, tougher than a common skeleton; undead), the **animated statue** (painted sandstone: it stands as still as stone until a player comes within 3.5 blocks or strikes it, then wakes for good), the **stone golem** (slow and very hard to hurt; its blows throw a player back; too big for the tomb's passages), and **Tahna** (a great monster: while any of the three canopic jars in her adventure is whole she rises again when struck down, weaker for each jar broken; she turns to dust and gathers again a few blocks away, sends whirlwinds of sand, and calls scarabs).

## The Queen's floor (mods/orthoverse_queens)

For Eight Queens and any builder's adventure, in the Creative tab: the **Queen's floor tiles** in eight colours (violet, orange, blue, green, grey, red, yellow, teal), each in a light and a dark shade and with its own pattern (so the colours can be told apart without telling colours apart), and a plain tile; the **doors of the throne room**; the **gilded rail**; the **Queen's banner**; the **Queen's throne** (the Queen sits on it, a still figure, set back by the throne after every restore); the **crown** on its cushion (a finish: it completes the adventure, in a run once the floor is solved); a **white plinth**; and the **notice** (how to play).

The puzzle (`mods/orthoverse_queens`) works on an adventure placed from the template `queens`: at the start of each run it finds the floor (the 24 by 24 tiles in the area: eight squares a side, three blocks each), makes a new puzzle (`puzzle.lua`: queens placed at random, a region grown from each, reshaped until there is one answer, and kept only if that answer can be reached by reasoning alone) and colours the floor. The kit gives eight **queens** and 99 **crosses**, set on a square with a right click (in its middle) and taken up by hitting them. When eight queens stand one to a row, column and colour, none touching, every door of the throne room in the area opens.
