# Dungeons on your land: implementation plan

> Some of this has been decided or built since: see [adventure-decisions.md](adventure-decisions.md) for the answers to the open questions (all suggested defaults accepted) and [adventures.md](adventures.md) for what exists. [adventure-runs.md](adventure-runs.md) supersedes the parts on sharing an adventure and resets; Zughy's Parties was replaced by our own party module (decision 29).

Draft, 8 Nov 2026 (revised after checking for existing mods, and with the combat direction agreed). Goal: a holder can build an adventure on their land ("something like" a frontier keep with a ravine of cave tribes, with original names and maps, not a copy of a published module) that visitors can play, alone or as a party. No code yet: this is the plan to agree first, kept up to date as decisions are made.

Related docs: [ideas-assessment](ideas-assessment.md) (assessment of every idea and the suggested order), [combat-numbers](combat-numbers.md) (first numbers), [adventure-design](adventure-design.md) (what makes modules popular, sample adventures), [builder-workflow](builder-workflow.md) (how a holder builds one), [accounts-plan](accounts-plan.md) (password characters), [monster-catalogue](monster-catalogue.md) (ready-made monsters).

Rule: use existing, maintained mods wherever they fit, and write only the glue that ties them to Orthoverse lands (who may use what, where, at which level). Second rule (8 Nov): every rule must hold up against a builder acting in bad faith (deathtraps, experience farms), since anyone at the unlock level can build an adventure.

## What exists already, and what we would write

| Need | Existing mod (checked 8 Nov 2026) | Ours to write |
| --- | --- | --- |
| Monsters | mobs_redo (engine) + mobs_monster (TenPlus1; ~40 monsters; MIT code, CC-BY-3.0 media; updated Oct 2026), and more packs on the same engine (see the catalogue). mobs_redo has its own spawner node; X Spawners API (SaKeL, LGPL, Nov 2026) is an alternative | Spawners only on adventure lands, monsters kept on their land, caps per land and overall, natural spawning off |
| Traps, secret doors | Mesecons (LGPL-3 / CC-BY-SA-3.0). Pistons and movestones already check protection before moving anything (setting `mesecon.mvps_protection_mode`); with our land protection they cannot push into a neighbour's land | Choose which parts to install; set the protection mode; per-land limits only if testing shows load |
| Loot chests | Treasure Chest (ZenonSeth; MIT; July 2026): each slot has a chance; every player has their own cooldown (minutes, or once only); owner configures; "simulate use" button; gives copies, so the chest never empties | Placeable only in creative mode on adventure lands; the policy for loot leaving the land |
| Parties | Parties (Zughy, author of arena_lib; AGPL-3.0 code, GPL-3.0 media; May 2025): invite, join, leave, kick, disband, leader handover, party chat (/p), an API for other mods. Simple Parties (fruitsnack; AGPL-3.0; Jan 2026; work in progress): ranks, a Parties inventory tab, shared party chests | Use Zughy's Parties; ours: what a party means in adventures (see below) |
| Builder tools | WorldEdit (sfan5) and WorldEdit Undo. WorldEdit does not check protection, and no mod on ContentDB restricts it to land a player owns | A thin layer: commands only when the selection lies inside your own land, volume cap by level |
| Dungeon reset | arena_lib (Zughy; AGPL) resets maps, but is a whole minigame framework (arenas, queues, matches): too much, wrong shape | Our own: the column save and restore from castle upgrades already keeps blocks, metadata and timers |
| No bones in dungeons; death and coming back | Minetest Game's bones has only a world-wide setting; on someone else's land it drops items on the ground. Nothing ready-made for downed players, ghosts, reviving or lockouts | Ours (see Death and coming back) |
| Arrival point, adventure switch, entry level range | Nothing fits our lands | Ours (small) |
| Combat beyond clicking | No complete system on ContentDB. Advanced Fight Library (SFENCE; MIT; work in progress) is a toolkit (hitboxes, armour, shields) using the Hitboxes library for boxes per body part; Nebula Combat tunes attack interval and knockback; 3d_armor for armour | The hold-and-release combat below (ours, on top of mobs_redo) |
| Great monsters with parts | Nothing ready-made found; the Hitboxes library (boxes per body part) may help. Big monsters exist as stand-ins (NSSM's kraken, tarantula, giant sandworm, lava titan; dragons) | Ours, plus models and animations (see below) |
| Character levels | xp_redo (mt-mods; GPL-2.0-only; maintenance only, last 2024): XP, ranks, a HUD bar, and an "xpgate" under a door that lets only players of a set level through. My Progress (Don; MIT; maintenance only): XP per skill with trophies. Neither ties levels to combat strength | Ours (small to medium), built into the combat; borrow the level-gated door idea |
| Characters and quests (not planned; option for later) | yl_speak_up (Sokomine, from the Your Land server; MIT; July 2026): branching dialogue, quests, trading. npc_talk adds the characters; npc_talk_edit edits dialogue in game | Only if other holders ask: grant its privilege by level |

So the big pieces (monsters, traps, loot, parties) all exist and are maintained. What we write is mostly permissions and limits, plus the combat, character levels, party rules, death rules and the great monsters.

AGPL note: Parties and arena_lib are AGPL. A server running AGPL code must offer its source (with any changes) to the players who use it. Our repository being public on GitHub, with a link from the site, covers that; worth confirming before adding it.

## Problems to fix first, dungeons or not

- **Plain chests:** a plain chest has no protection check: anyone can open one on any land. A holder who fills one in creative mode lets visitors carry creative items off the land, which the inventory swap exists to prevent. Fix (small, ours): on private lands (level 1+, not crofts), plain chests open only for the holder. Worth doing before the playtest.
- **Players can hurt each other everywhere:** the server has damage on and Luanti's player-against-player setting (enable_pvp) is on by default, so today any player can attack any other anywhere. Decide before the playtest: off everywhere (simplest), or on only in chosen places. With parties, members should never hurt each other.

## Phases (each a patch Keir can test on its own)

1. **Adventure mode and arrival point** (small, ours). `/adventure on` for a land from a level to decide (suggest 5; the admin anywhere); `/arrival` sets where visitors arrive (used by /goto, the map and henges); the entry level range; no bones there; the death lockout; the land line at the bottom left says "Adventure".
2. **Monsters** (medium: mobs_redo, chosen monster packs, our glue). Natural spawning off everywhere; spawners only in creative mode on adventure lands; monsters that leave their land removed; caps; monsters never break blocks.
3. **Combat: hold and release** (medium, ours; see below). Comes with or right after the monsters, since it decides how fighting them feels. Could itself be split: first timing (hold) and distance, then aim (where you hit), then monster wind-up tells, then shields.
4. **Character levels** (small to medium, ours; see below). Right after the combat, since levels feed into its sums; monsters get a level when they are placed.
5. **Death and coming back** (medium, ours; see below). The solo rules and the lockout come with phase 1 or 2; the party rules (downed, ghost, revival) with phase 6.
6. **Parties** (small to medium: Zughy's Parties, our adventure rules; see below). Can come as soon as monsters and combat exist; experience sharing needs character levels.
7. **Mesecons** (small: mostly configuration). Wires, levers, buttons, pressure plates, detector, delayer, gates, lamps, pistons, movestones, noteblock. Leave out the programmable controllers (luacontroller, microcontroller, FPGA) and the command block.
8. **Loot** (small: Treasure Chest, our glue), once the loot policy is decided.
9. **Reset** (medium, ours). `/adventure save` and `/adventure reset`, plus automatic reset after a time with no visitors (never while a party is inside).
10. **Builder tools** (small to medium: WorldEdit and WorldEdit Undo, our land check and caps). Delegate (from the later-abilities list) lets friends build together.
11. **Great monsters with parts** (large, mostly art; see below). After the combat has been played and tuned: one monster first (the hydra), then others.
12. **Rune magic** (later; see below).

Not planned: characters to talk to and quests. Keir finds talking to monsters and characters annoying (8 Nov 2026): adventures tell their story through signs, books and the place itself, and the tribes simply fight. yl_speak_up and npc_talk remain an option to offer other holders later if they ask, at little cost.

To check while building each phase (not yet verified): the exact options of mobs_redo's spawner, and whether its monsters can be set to fight other kinds (for rival tribes); how Treasure Chest gives items when the player's inventory is full; what Zughy's Parties API offers (party members, leader, join and leave events); how well a player can be attached to another as a watching ghost in Luanti (camera, hiding, the browser client); licences side by side (xp_redo is GPL-2.0-only, one reason to write our own levels; Parties is AGPL).

## Combat: hold and release (direction agreed 8 Nov 2026)

Inspired by Ultima Underworld: fighting is about timing, aim and footwork, not clicking fast. Decided by Keir: no visible dice or armour class numbers (players only need to know that one weapon or piece of armour is better than another); no food, carrying weight, burning-out torches or self-drawing map (too much computation, not interesting); one attack button, no separate bash, slash and thrust controls; different weapons reward different holds (a short sword gains little beyond a brief hold, a broadsword or bastard sword gains a lot); where the crosshair is on the monster and how close you are both count.

Each blow is judged on three things: **timing** (the hold), **aim** (where on the monster) and **distance** (your footing). Character level (below) sets how much room for error a player has and how hard they hit. First numbers: [combat-numbers](combat-numbers.md).

### Timing: the hold

- Hold the attack button to wind up, release to strike. The server sees the button go down and up and times the hold. Ordinary click-punching does nothing to monsters on adventure lands.
- Each weapon has its own wind-up curve: how soon it is ready, when it reaches full strength, and how quickly it weakens if held too long (a tired arm). A dagger or short sword is ready almost at once and gains little; a broadsword or bastard sword is weak when snapped off and strong at full wind-up. The skill is releasing at the right moment.

### Aim: where the blow lands

- On release the server traces a line from the player's eye along their view (Luanti's raycast), which gives the exact point where it meets the monster and the distance to it.
- Height on the monster: head, body or legs, from where that point falls on the monster's box. A head hit does extra damage or briefly stuns.
- Side: front, side or back, from the attack direction against the way the monster faces. A blow from behind hits harder, rewarding working round an enemy instead of charging in (and rewarding parties that surround one).
- Limit: Luanti gives a monster one rectangular box, not its true shape, so "head" means the top of the box. Good enough for most monsters; for odd shapes the Hitboxes library used by Advanced Fight Library gives a box per body part, and the great monsters below use separate parts.

### Distance: footwork

- Each weapon has a best range as well as a best hold: a spear at full reach, a dagger close in, a sword in between. At the edge of its reach a blow glances; beyond it, it misses.
- With the monsters' wind-up tells (below), this makes stepping in to strike and out when they wind up the core of a fight.

### What the player sees

- A charge bar at the bottom of the screen with the weapon's sweet spot marked on it; the weapon swaps to a "raised" picture while winding up and a "ready" one at the sweet spot; Luanti's own swing on release; a brief miss, glance, hit or head-hit marker over the target. The shape of the bar shows how weapons differ without any numbers.

### Weapons and armour

- Attack type (thrust, slash, bash) comes from the weapon, not the hold time: daggers and spears thrust (good against light armour), swords slash (all-round), maces and hammers bash (knock back, good against heavy armour). Claude's view: tying the type to hold time would be invisible to players and hard to show; tying it to the weapon is clear and still gives every weapon its own feel. The hold decides how strong the blow is.
- Hit and damage are worked out behind the scenes from weapon, hold, aim, distance, the attacker's level and the target's armour and level (the SRD 5.2 attack roll against armour class, CC-BY-4.0, is the model; never shown). Armour from 3d_armor if it fits.
- Each weapon is then a small set of numbers: wind-up curve, best range and reach, attack type, damage. New weapons are cheap to add.

### Monsters

- Monsters wind up too, with a visible tell (a pause, a raised arm, a sound), so players can step back out of reach or strike first. This is what makes it more than trading blows.
- Monster armour and weak spots by type (for example a heavily armoured monster that a mace handles best, or one that must be hit from behind).
- In a party fight, a monster turns on whoever has hurt it most recently or most (so one player can draw it while others strike from behind).

### Lag

- The server judges where the monster was at the moment of release; what the player sees is a little behind (a tenth of a second or more through the browser client). For slow, deliberate fights that is fine, provided the head zone, the back arc and the sweet ranges are generous rather than pixel-exact, so players are not cheated on hits that looked right on their screen. Tune by playtesting.

### Later

- Hold right-click with a shield to block: less damage, slower walking. In a party, the shield-bearer holds the monster's attention.
- Applies on adventure lands first; the rest of the world keeps Minetest's combat. Whether it later spreads to the whole world is a separate decision.

Technical notes: Luanti's first-person weapon animation is fixed and the server cannot change it, hence the picture swap. The release is noticed within a server step (about a tenth of a second), fine for deliberate swings.

## Character levels (Keir's idea, 8 Nov 2026)

As a player's character level rises they can take on tougher monsters, and easy monsters become trivial to kill. This replaces the earlier suggestion (Claude's) to leave character progression out.

### Name

- "Level" already means a land's castle level. To avoid confusion, call the character's level something else to players: for example **rank** or **renown** ("Renown 7"). To decide.

### What a level does

- A higher level gives more health, hits harder and more surely, and takes less from each blow, all behind the scenes (the SRD's proficiency bonus that grows with level is the model).
- Proposed: it also makes the combat more forgiving: a wider sweet spot on the charge bar and a larger head zone. The skill of timing, aim and footwork still matters at every level, but an experienced fighter has more room for error. (Claude's suggestion; it keeps levels from simply erasing the combat.)
- What matters is the gap between the player's level and the monster's: a monster well below you dies in a blow or two and barely scratches you; one well above you is very hard to hit and hits very hard. That is what makes easy monsters trivial and tough ones a goal.

### Monsters have levels too

- Every monster has a level, set by the builder when placing a spawner ("these goblins are level 3"), within a range suited to the monster type. Great monsters (hydra, giant spider) are high-level bosses.
- No numbers on monsters: the colour of a monster's name or marker shows how it compares with you (grey: trivial; green: easy; yellow: even; orange: hard; red: deadly), as in many online games.
- An adventure shows its recommended level, its level range and party size at the entrance (on a sign, the land line at the bottom left, and the map panel).

### Who may enter: the level range (Keir's idea, 8 Nov 2026)

- Each adventure has a lowest and a highest character level allowed in, set by the builder (suggested default: the recommended level minus 1 to plus 4). Players outside the range cannot enter the adventure's land; they are told why and what the range is.
- The maximum matters as much as the minimum: in one shared world, a high-level player in a beginners' adventure would not only gain nothing, they would clear its monsters before the beginners got there. The maximum keeps beginner adventures for beginners.
- A party enters only if every member is within the range.
- Inside an adventure, level-gated doors (below) can still split it into an easier and a harder part.
- Optional later: a "mentor" exception, where a high-level player may join a low party but fights at the adventure's top level, gains nothing and cannot finish it.

### Earning levels

- Experience from defeating monsters, more for those at or above your level, none for trivial ones (so farming easy monsters gets you nothing).
- Only for monsters that were really fighting (they attacked or hurt someone in the last few seconds), so a builder cannot make an experience farm of trapped monsters that cannot fight back.
- Less experience from the same spawner again and again within a day, so a player cannot camp one spawner; a daily cap per adventure per player.
- No experience for the builder and their delegates on their own adventure.
- In a party, experience is shared among the members near the kill (see Parties).
- A bonus for finishing an adventure (reaching its end, opening its final chest), once a day per adventure.
- A level cap, for example 20, with each level needing more experience than the last.
- Dying never costs experience or levels (see Death and coming back).

### Where it shows

- The player's level and a progress bar on screen while in an adventure; on the Account page; perhaps a leaderboard.
- Level-gated doors for builders (the xpgate idea from xp_redo): a door that only opens for players of a set level, so an adventure can have a deeper part for experienced players. For a party, the door could open if every member qualifies, or the leader does (to decide).

### Principles

- Character level is earned by playing, never bought: castle levels (from the token) give building powers, not fighting strength. This keeps adventures fair and avoids presenting the tokens as paying for power.
- Levels belong to the player (their wallet name or password character), kept in the game's player data; guests (not signed in) can fight but do not keep levels, or keep them only for the session. To decide.
- Levels count only in adventures, like the combat, unless that changes later.

## Parties (Keir's idea, 8 Nov 2026)

Players want to take on adventures together: several players can kill monsters too tough for one. The party itself (forming, inviting, leaving, party chat) comes from Zughy's Parties mod; what we add is what a party means in an adventure.

### Forming and finding a party

- From Parties: `/party invite <player>`, `/party join <player>`, `/party leave`, `/party kick`, `/party disband`, party chat with `/p`; the leader role passes on if the leader leaves.
- A size limit (suggest 6), so an adventure for four is not flattened by twelve.
- Later: a way to find people to play with, such as a "looking for a party" board on the website or a notice board at the henges.

### Getting there together

- When the leader goes to an adventure (by /goto, the map, a henge or the gateway), members can follow with one command (`/party follow` or similar) and arrive at the same arrival point. Only into adventures, only if every member is within its level range and not locked out, and never for a member who has died in the current run.

### Seeing each other

- Party members' names and health shown in a small panel on screen (a few bars, one per member, with downed, dead and locked-out members marked), only while in an adventure.
- Members' name tags in a party colour, and a marker on screen pointing to members on the same land, so a party split up in the caves can find each other.

### Fighting together

- Party members can never hurt each other.
- Monsters do not get weaker or stronger by party size: a party of four beating a monster too strong for one is the point. What stops big groups trivialising everything is the experience rules, the party size limit, the level range, the death rules, and builders choosing monster levels for their intended party size.
- Monster attention (from the combat section): the monster turns on whoever hurt it most recently or most, so roles appear naturally: one draws it (with a shield, later), others strike from behind. Great monsters are made for parties (the hydra: one cuts, one burns).

### Sharing the rewards

- Experience for a kill is shared among the living party members near it, each by their own level against the monster's level. A small bonus for fighting together (for example the total is a little more than one player would get) makes parties worthwhile without making solo play pointless.
- Loot: loot chests already fill for each player separately (Treasure Chest), so there is nothing to argue over; every member opens their own. A boss trophy, if there is one, goes to every member present (including those who fell in the fight, as ghosts; to decide).

### Sharing an adventure with other parties

- One shared world: two parties can be in the same adventure at once, and the second may find monsters already killed and chests opened (their own loot is still waiting for them, since chests fill per player).
- Option for builders, later: "one party at a time": the entrance only opens when nobody else is inside, with others told how long the current party has been in. This needs a clear entrance (a door with a detector, Mesecons) and a time limit so a party cannot hold an adventure for ever.

### Guests

- Whether guests (not signed in) may join parties follows the guest decision for adventures.

## Death and coming back (Keir's concerns, 8 Nov 2026)

Two problems: a party member who dies must not simply reappear and run back to keep helping, or death means nothing and a party can grind down any monster; and there should be a cost to dying. Keir's second point: the cost must not take anything lasting away (a level, or experience), because builders could make deathtraps to drain visitors. His proposal, adopted: being kept out of that adventure's land for a while.

### A "run"

- A run starts when a player (or the first member of a party) enters an adventure, and ends when every member has left it, or every member is dead (a wipe), or after a time limit (for example two hours) so nobody is stuck.
- The rules below apply on adventure lands. Outside adventures, dying works as in the rest of the world.

### The rules

1. **Downed first, not dead.** When a player's health runs out in an adventure, they fall and are downed for a short time (for example 30 seconds): they cannot move or fight, monsters lose interest in them, and their marker shows to the party. A living party member who reaches them and holds the use button on them for a few seconds (in danger, since they cannot fight meanwhile) brings them back on their feet with a little health. This is the moment of drama, and it is a choice: save a friend or keep fighting.
2. **Then a ghost (in a party).** If nobody revives them in time, they die. In a party they become a ghost: invisible, unable to touch anything, following the party (attached to a living member, or free to float within the adventure, to test which works better in Luanti). They can still talk in party chat and watch, so they stay part of the evening, but they cannot help. Solo players skip this and come back outside at once.
3. **Locked out.** After dying, a player cannot enter that adventure's land (or lands) for a while, by walking, /goto, `/party follow`, the map or a henge. Suggested: 10 minutes for the first death, doubling for each further death in the same adventure within a few hours (10, 20, 40, at most 60 minutes), the count clearing the next day. In a party, a dead member is out at least until the run ends, and longer if their lockout says so. A party that wipes is locked out together, so a boss cannot be worn down by instant retries. They come back outside the adventure (just beyond its land, or at their own home), never inside it.
4. **Revival at a price (optional, later).** A rare item found in the adventure (a revival potion, or a resurrection rune if rune magic comes) lets a living member bring a ghost back at a shrine or where they fell, which also lifts their lockout for that run. Builders decide whether their adventure has any.

### Why a lockout and nothing else

- It costs only time, and only in that adventure: every other adventure and the rest of the world stay open, so nobody is ever stuck with nothing to do.
- A builder's deathtrap can at worst keep people away from that builder's own adventure, which harms only the builder. Nothing a builder makes can take levels or experience from a visitor.
- **No loss of experience or levels, ever.** Losing a level was considered and dropped: it drives players away, clashes with level-gated doors and entry ranges, and (Keir's point) would turn deathtraps into a way of draining players.
- A short "weakened" spell after coming back is not needed with a lockout; optional later if lockouts prove too mild.
- No damage to equipment (it would need durability tracking, which Keir ruled out with food and weight).

### Dealing with deathtraps

- Builder statistics show deaths per room; an adventure with an unreasonable death rate, or reports from players ("report this adventure" on the map panel), can be closed by the admin.
- A new adventure could be marked "untested" until a few players have finished it.

### Wipes

- If the whole party is downed or dead, the run ends: everyone comes back outside, locked out together. Monsters the party hurt heal; a great monster returns to full strength (and a hydra keeps any extra heads it grew). The builder may choose that the adventure resets for the party's next try.

### Technical notes

- Luanti lets the server stop a player dying (catch the health change), freeze them (physics overrides), hide them (visual properties) and take away interaction (privileges), so downed and ghost states are possible without engine changes. Following a member as a ghost uses attaching one player to another; how well the camera behaves, especially in the browser client, needs testing.
- The lockout is a list of (player, adventure, until when), kept in mod storage so leaving and rejoining does not clear it; entry is checked wherever a player can arrive on a land (walking across its border, /goto, /home, the map, henges, party follow).

## Great monsters with parts (idea, 8 Nov 2026)

Keir's idea: large monsters where parts can be disabled before the whole is killed, such as a giant spider whose legs can be cut off or a hydra whose heads can be severed, where taking parts off is sometimes the right approach.

### How it can work in Luanti

- One monster made of a main body plus parts (legs, heads, a tail), each with its own hit area and its own health. Two ways to give parts their own hit areas: small invisible entities attached to the model's bones, which move with its animation and which the hit check (the raycast on release) can tell apart; or the Hitboxes library's boxes per body part. Which one works better is to be tested.
- When a part's health runs out it is severed: the part is hidden on the model (Luanti can shrink a bone to nothing from the server, so one model serves before and after), a loose severed part falls to the ground for effect, and the monster changes.
- Each part changes the fight when lost, which is what makes cutting parts off a choice and not just damage in a different place:
  - Giant spider: each leg lost makes it slower; with too few legs it collapses and its body (the real target) comes within reach. Its fangs are dangerous at the front, so working round to the legs is the safer way in.
  - Hydra: each head attacks on its own and has its own wind-up tell. A severed head regrows (two in its place) unless the stump is burned with fire within a few seconds, as in the myth; the body only takes damage once all heads are gone. Here the right approach is a team: one cuts, one burns.
  - Others to consider: a beast whose armoured tail must come off before its back is open to attack; a golem whose arms can be broken to stop its slams.
- The weapon types matter here too: slashing weapons are best at severing, thrusting at piercing the body once open, bashing at breaking armoured parts.

### Size and place

- Great monsters belong in large rooms built for them (a pit for the hydra, a cavern for the spider). Large monsters find their way badly through narrow tunnels, so the builder places them as a boss in their own room. The hydra can stay rooted in its pit, which also keeps it simple.
- One great monster per adventure, or a small number per land, counted in the monster caps. Each is a handful of objects, fine for the server.

### Cost

- The code is medium: parts, their health, severing, regrowing and the effects, on top of the combat phase.
- The art is the larger part: each great monster needs its own model with bones and animations (walking, each attack's wind-up, collapsing), made in Blender. Existing big monsters (see the catalogue) can stand in for testing, but a proper giant spider and a hydra need new models. Finding or commissioning these is the main cost and should be planned early.

### Later variations

- Parts as trophies: a severed hydra head as the adventure's trophy (fits loot option C), one for each party member present.
- Builders choosing their great monster from a small set made for the game, not making their own.

## Rune magic (later, keep in mind)

Runestones found in adventures, combined in a small rune bag to cast spells (the Ultima Underworld idea). Not planned in detail yet. Fire for burning hydra stumps could be one of the first spells, or simply a torch or fire item. Spells could open up with character level; healing and a rare resurrection spell would give parties a supporting role.

## Decisions for Keir

1. Which level unlocks adventure mode, spawners and Mesecons (suggest 5; the admin anywhere), and how caps rise with level.
2. Monsters in the wild at night: yes or no (suggest no at launch).
3. Monster drops: none, a small fixed set, or the loot rules.
4. Loot leaving the land: A. real items from an allowed list, limited per day; B. loot stays in the adventure (a visitor's own inventory is put away on arrival and given back on leaving); C. B plus a trophy that does leave (suggested).
5. Guests (not signed in) in adventures: yes or no (suggest yes); whether guests keep character levels; whether they may join parties.
6. The Mesecons parts list above: more or fewer.
7. Combat: attack type from the weapon (suggested) or from the hold time.
8. Combat: what a head hit does (extra damage, a short stun, or both) and how much a blow from behind adds.
9. Great monsters: which first (suggest the hydra: rooted, so simpler, and its burning puzzle shows the idea best), and where the models come from (made for us, or found with a suitable licence).
10. Character levels: the name players see (rank, renown, or another), the level cap (suggest 20), and whether higher levels also widen the sweet spot.
11. Parties: the size limit (suggest 6), the group experience bonus, whether a level-gated door needs every member or only the leader to qualify, and whether builders get the "one party at a time" option.
12. Players hurting each other: off everywhere (suggest, at least for the playtest) or only in chosen places. Decide before the playtest, since it is on today.
13. Death: downed then ghost (decided in principle: no running back); the lockout lengths (suggest 10 minutes doubling to an hour); whether revival items exist; whether fallen members share a boss trophy.
14. Entry level range: the default range (suggest recommended level minus 1 to plus 4), and whether to offer the "mentor" exception later.

## Sources

- Mobs Monster: https://content.luanti.org/packages/TenPlus1/mobs_monster
- X Spawners API: https://content.luanti.org/packages/SaKeL/x_spawners_api/
- Mesecons (mvps protection code): https://github.com/minetest-mods/mesecons
- Treasure Chest: https://content.luanti.org/packages/ZenonSeth/treasure_chest/
- Parties (Zughy): https://content.luanti.org/packages/Zughy/parties/
- Simple Parties: https://content.luanti.org/packages/fruitsnack/simple_parties/
- Yourland Speak up: https://content.luanti.org/packages/Sokomine/yl_speak_up/
- npc_talk: https://content.luanti.org/packages/Sokomine/npc_talk/
- WorldEdit packages on ContentDB: https://content.luanti.org/packages/?q=worldedit
- arena_lib: https://content.luanti.org/packages/Zughy/arena_lib
- Advanced Fight Library: https://content.luanti.org/packages/SFENCE/advanced_fight_lib/
- Nebula Combat: https://content.luanti.org/packages/JoinNebula/nebula_combat/
- xp_redo: https://content.luanti.org/packages/mt-mods/xp_redo/
- My Progress: https://content.luanti.org/packages/Don/myprogress/
- SRD 5.2 under CC-BY-4.0: https://www.dndbeyond.com/posts/1949-you-can-now-publish-your-own-creations-using-the
