# Adventures: critical review of the plan (8 Nov 2026)

Keir asked for a reassessment of the whole adventure plan: its weaknesses, which choices are best, how feasible it is, and what situations have not been considered. This reviews [dungeons-plan](dungeons-plan.md), [adventure-runs](adventure-runs.md), [ideas-assessment](ideas-assessment.md), [combat-numbers](combat-numbers.md), [accounts-plan](accounts-plan.md) and [builder-workflow](builder-workflow.md). No code.

## Summary

- The direction is sound and feasible. Most of the risk is not technical: it is whether enough players come to make queues, parties and league tables matter, and whether there is time to build the adventures themselves.
- Several technical assumptions are unproven and should be tested with small experiments before the big pieces are built (list below).
- Some earlier recommendations should change: a slimmer first milestone, our own small party system instead of an AGPL mod, checkpoints for long dungeons, a solo path through every adventure (with hired companions), protection for private copies, and some guard against cheating once there are league tables.
- Calibration: this week's work was about 30 patches (0036 to 0064) in two days. The adventure plan is roughly 35 to 45 patches plus art, so a few weeks of steady work, not months, provided the experiments go well.

## The biggest weaknesses

### 1. It assumes players we do not have yet

Queues, parties, league tables, weekly tables, party-finding boards and private copies all assume a busy server. Today the population is Keir and a handful of testers. With few players:
- league tables have one or two names in them;
- parties are hard to form, so any adventure that needs a party (the hydra: one cuts, one burns) cannot be played;
- private copies and queues solve a problem that will not exist for a long time.

What to do: build for a small population first and let the busy-server features follow demand. Every adventure must be completable solo (see hired companions below). Start with one party at a time (B); build private copies (C) only when queues actually appear. Launch league tables in their simplest form (per adventure: who has completed it, fastest), and add the rest when there are enough names to compare.

And measure: weekly returning players and adventure completions, from the game's own records, so decisions follow real use.

### 2. The first milestone was too big

As written, milestone 1 (The Three Bells) needed adventure mode, the gate, level ranges, the queue and reset, Mesecons, loot chests, the adventurer's kit, the lockout, league tables and the Adventures page. That is most of the system before anything is playable. The Three Bells is a puzzle tower with no combat, so it needs neither the kit nor levels nor the lockout.

Slimmer milestone 1: adventure mode with arrival point and gate, Mesecons, a finish block, one party at a time with a reset after each run, and a simple completions list (who, when, how long) shown on a board and on the website. Everything else moves to milestone 2 with the combat, where it is needed.

### 3. The content is the real bottleneck

Four sample adventures are a lot of building. A good one-land dungeon is days of work in Luanti. The plan schedules builder tools for holders late, but Keir, as admin, can use WorldEdit now. Recommendation: install WorldEdit for the admin early (it is a privilege matter only), build the samples with it, and give holders the land-limited version later. Recruit one or two builders from the old community for the samples.

There is also no incentive for holders to build adventures beyond pride. The card showing "completed 37 times" and a builders' table help. Keep it there: anything paid would look like the tokens earn income, which the abilities principles rule out.

### 4. Unproven technical assumptions

These should be tested with small experiments (an afternoon each) before the dependent work is built:

1. **The browser client with monsters.** Twenty monsters with animations, particles and the extra HUD (charge bar, party panel) in luanti-wasm on an ordinary laptop: is the frame rate acceptable? Everything else depends on this.
2. **Holding the attack button.** While the button is held at a monster, the client keeps punching it every so often; at a wall it tries to dig (refused by protection, which also prints "Step onto your land" messages and shows cracks). The combat layer must ignore the client's own punches, stop the dig attempts and messages in adventures, and detect release reliably through the browser client. Likely fine, but it is the core of the design and must be proven first.
3. **Hooking mobs_redo.** Replacing its damage handling with ours, adding wind-up tells and per-player attention, without forking it. If mobs_redo resists this, the alternative is our own light monster behaviour on creatura (already in the game for animalia, built for custom behaviour), using mobs_monster's models and textures.
4. **Copying a dungeon (private copies, C).** How long does pasting one land's dungeon take, spread over steps so nobody's game stutters? Decides B versus C later.
5. **Ghosts.** Attaching a dead player to a living one, invisible, with a usable camera, in the browser client. Fallback: a free ghost that cannot leave the dungeon area.

### 5. Licences and the AGPL mods

Zughy's Parties is AGPL. That obliges offering the server's source to players. If the repository stays public, fine; if it is ever private, it is a problem. A party system for our needs is small (invite, accept, leave, party chat, a roster for runs) and needs to be woven into runs anyway. **Revised recommendation: write our own small party module**, borrowing Parties' command names so it feels familiar. Use existing mods where they are permissively licensed (mobs_redo MIT, Treasure Chest MIT, Mesecons LGPL).

### 6. Complexity for players

Inventories: building, creative (on your land) and now the adventurer's kit. Death: downed, ghost, lockout. Levels: castle level and character rank. Each rule is sensible; together they are a lot to explain. What to do:
- Every rule appears on screen at the moment it matters ("Downed: a friend can help you up for 30 s"; "You can return to The Gullet in 9 minutes"; "Your kit is out: this is an adventure").
- The kit switch happens at the gate, never by surprise.
- One short "How adventures work" page on the website, and the same text in the game at the first adventure.

### 7. Moderation falls on one person

Reports, renames, deathtrap reviews, disputed records, account recovery: all Keir. Keep rules mechanical where possible (automatic death statistics, automatic flags for impossible times), give the admin quick commands (close an adventure, remove a record, rename a player), and consider a second admin before the launch.

## Situations not yet considered

### Long dungeons and checkpoints
A death near the boss after 40 minutes, then a lockout and a full replay, is harsh, especially solo. Options: checkpoints the builder places (a shrine where a downed or dead player of the run returns, once, instead of being locked out; using one counts as a death in the record); or shorter dungeons. Recommendation: allow up to two checkpoints per adventure; a run with checkpoint returns is still a completion, with its deaths counted.

### Solo players and parties that are too small
With few players, party-only content is dead content. Ideas:
- **Hired companions:** a fighter or archer hired at the fort (no talking: a sign with a price in adventure coins, or free for the first adventures) who follows and fights, simple behaviour on the monster engine. Fills a party role for a solo player; a companion cannot revive or finish.
- **Solo-friendly great monsters:** the hydra's fire could come from braziers the player knocks over, not only from a second player.
- League tables already separate solo runs.

### Cheating on league tables
Once records exist, people will try: modified clients (Luanti's server has basic movement checks, but they are not airtight), using glitches (monsters stuck on blocks, Mesecons tricks, getting past walls). Measures: record which way each run went (checkpoints passed, time at each); flag times far below the norm for the admin; a "verified" mark only after the admin has looked at the top record; keep Luanti's anticheat on (it is on by default; nothing in our settings turns it off). Not perfect; enough for a small community.

### Private copies need their own protection
Everything in the game protects by land; the reserved space for copies is not a land, so nothing would stop a visitor digging through a copy's walls or breaking its blocks. Copies need their own rule: inside a copy, only the run's own rules apply (no digging, no building, Mesecons only as built). Also: the land line at the bottom left, the minimap and the map service must treat the copy as the adventure, not as empty space.

### Where adventure templates live
Saved adventures (the state every reset restores) can be large. They belong in files in the world folder, not in mod storage (one database, unsuited to large blobs), and the nightly backup already covers the world folder. Versions kept for the league tables add up: keep the current version and the last two.

### The holder's own use of the land
A land with an adventure on it is also the holder's land. The dungeon area (inside the gate) belongs to the adventure; the rest of the land (the fort, the surroundings) stays the holder's to build on and is open to visitors as usual. The gate marks the boundary. If the holder builds inside the dungeon area while it is open, it changes the run for players: building there only while closed.

### Adventures spread over several lands
If one of the lands is sold, the adventure is broken. Rule: an adventure spans only lands held by the same wallet; if that stops being true, it closes automatically and the holder is told.

### Two progressions stacking
Character rank and gear from the kit both make a player stronger. Stacked, a high-rank player in top gear could trivialise everything within the level range. The level range keyed to rank, and loot tiers keyed to the adventure's range, keep this in check; tune with the combat test harness.

### Accessibility
Hold-and-release timing is hard for some players (motor difficulties, or a laggy connection). The sweet spot widening with rank helps. Consider an "easy timing" option (a wider sweet spot) that marks the player's records as assisted, so they can play and still appear in tables, in their own column.

### Night, weather and the outside world
The arrival point is outdoors; night and rain carry on as usual. Inside, dungeons are lit by the builder. Nothing to change, but builders should know torches are needed; the builder's guide says so.

### Holders and their own adventure
A holder in creative mode on their land, with fly and noclip, is next to their own dungeon. The gate must switch creative mode off and the kit on for anyone entering as a player, holder included; the holder's test mode (from the builder workflow) is the only way to play it with their abilities off but without records.

### Guests in adventures
Guests have no lasting identity, so no records, no kit kept, no rank kept. They can try The Three Bells (no combat) as a taster; combat adventures could ask them to make a password character first. That turns adventures into a reason to sign up.

### Security of a bigger auth service
Password characters, recovery codes and more endpoints make the auth service a bigger target. Slow password hashes (scrypt), rate limits (already in place), Turnstile, no email stored, and the same test suite discipline as now. Worth a security pass before launch of accounts.

### What happens to the launch plan
None of this should delay the relaunch. The launch needs: the plain-chest fix, player-against-player off, password characters (recommended), and the playtest. Adventures follow, The Three Bells first.

## Which choices are best (and which change)

Keep:
- **Hold-and-release combat**, attack type from the weapon, hidden numbers on the SRD 5.2 model.
- **Lockout as the death penalty**, no experience or level loss (deathtrap-proof).
- **Entry level ranges**, whole party must fit.
- **Password characters before the playtest**: still the single most valuable item.
- **One party at a time first**, private copies when demand shows.
- **The adventurer's kit**: keeps the building economy clean while gear progresses (but explain it well).
- **The Three Bells first**: proves adventures, Mesecons, runs and completions without combat.
- **Characters to talk to: not planned.**

Change:
- **Milestone 1 slimmer** (no kit, levels or lockout; a simple completions list).
- **Our own small party module** instead of the AGPL Parties mod.
- **WorldEdit for the admin now**, land-limited builder tools for holders later.
- **Checkpoints** in longer adventures.
- **Solo path in every adventure**, hired companions as the way to fill party roles.
- **Five experiments first** (browser client with monsters, holding the button, hooking mobs_redo, copying a dungeon, ghosts).
- **Protection for private copies**, templates stored as files, versions limited.
- **Simple league tables first**, with flags for impossible times.

## Feasibility, by milestone (rough patch counts)

| Milestone | Contents | Patches | Notes |
| --- | --- | --- | --- |
| 0 | Plain chests, players cannot hurt each other, password characters | 4 to 5 | Before the playtest |
| Experiments | The five tests above | 3 to 5 | Small, throwaway or kept as foundations |
| 1 | Adventure mode, gate, Mesecons, finish, one party at a time with reset, completions list; The Three Bells built | 5 to 7 | Plus building time for the adventure |
| 2 | Monsters, hold-and-release combat with distance, character rank, kit and loot, lockout, entry ranges; The Gullet built | 8 to 10 | Plus building time; combat tuning by playing |
| 3 | Aim, monster tells, our party module, downed and ghost, checkpoints, companions, shields | 6 to 8 | |
| 4 | Land-limited builder tools, delegate, builder statistics, reports, builder's guide | 3 to 4 | |
| 5 | The Fallen Star; private copies if queues appear | 3 to 6 | Robot models |
| 6 | Great monsters, The Drowned Pit | 4 to 5 | Plus the hydra model (commission early) |
| Later | Rune magic, weekly tables, cards showing completions | as wanted | |

Roughly 35 to 50 patches plus art and building time. Technically feasible in Luanti without engine changes, if the experiments confirm the client and the combat input behave.

## Decisions this review adds for Keir

1. Slim milestone 1 as above (suggest yes).
2. Our own party module instead of Zughy's Parties (suggest yes, given AGPL and the run roster).
3. WorldEdit for the admin now (suggest yes).
4. Checkpoints (suggest up to two per adventure).
5. Hired companions for solo players (suggest yes, in milestone 3).
6. Guests: puzzle adventures only, combat adventures need a character (suggest yes).
7. A second admin before launch (suggest finding one).
8. Run the five experiments before milestone 2 (suggest yes; the first two before anything else in combat).
