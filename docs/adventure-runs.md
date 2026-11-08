# Adventure runs: sharing, resets, league tables and the awkward cases (8 Nov 2026)

Keir's questions: what happens when a party has cleared half a dungeon and another party comes in? How do resets work after a dungeon is completed? And there should be a league table of who has completed each dungeon, for comparison and competition. This doc works through those, and the other awkward cases they lead to. It supersedes the "Sharing an adventure with other parties" part and the reset phase of [dungeons-plan](dungeons-plan.md). No code.

## The core problem: one shared world

Luanti has one world. If two parties are in the same dungeon at once, the second meets dead monsters, sprung traps and open doors; the first can drag monsters onto the second or steal their kills. A league table then means nothing, because the second party had half the work done for them. So the way parties share a dungeon decides whether a league table is possible at all.

## Three ways to share a dungeon

### A. Everyone in the same dungeon (the plan as first written)

- Simple, but unfair, griefable, and makes league tables meaningless. Resets can only happen when the dungeon is empty, which a popular dungeon never is.
- Assessment: **not good enough** once there are league tables. Fine only for casual "walk in" areas without a finish.

### B. One party at a time, reset between runs

- The dungeon has one entrance (a gate at the edge of the dungeon area, which the builder marks). While a party is inside, the gate is shut; others wait at the arrival point (the fort or camp) and see who is inside, for how long, and their place in the queue.
- When the run ends (the party finishes, leaves, wipes, or hits the time limit), the dungeon is restored from its saved state, "restocking" for a minute, and the next party in the queue is called.
- Every party starts from the same state, so league tables are fair.
- Uses the save-and-restore we already have for castle upgrades, run on the dungeon area only.
- Weakness: a popular dungeon has a queue; a slow party holds it for everyone (the time limit, set by the builder within bounds, for example 30 to 120 minutes, handles this).
- Assessment: **the place to start.** Little new machinery; fair; queues are a nice problem to have.

### C. A private copy for each party (instances)

- The dungeon on the holder's land stays as the template. When a party enters the gate, a fresh copy of the dungeon is pasted into a reserved space far from the playable world (for example deep underground, around y = -20000, where nobody can dig to and the mapgen makes nothing) and the party is moved into it. When the run ends, the copy is wiped.
- Several parties play the same dungeon at the same time, each in their own copy; no queue; no reset needed (every run starts from a fresh copy); the template on the land is never touched by visitors.
- The machinery is the same save-and-restore as B, pointed at a slot in the reserved space instead of at the land, plus moving the party there and back, and keeping monsters, spawners and wiring working in the copy.
- Costs: copying a dungeon is a lot of blocks (one land, full height, is about 1.8 million nodes); done in one go it would make everyone's game stutter, so it must be spread over several seconds while the party waits at the gate ("The way opens..."). A cap on how many copies run at once (for example 6), queueing beyond that. The map tiles, minimap and the land line must not show the reserved space as a place (the land line shows the adventure's name).
- Assessment: **the better end state.** Fairest, no queues, and it makes resets disappear as a problem. Worth a feasibility test early: how long does pasting one land's dungeon take on the ProLiant, spread over steps? If it is a few seconds, go straight to C; if not, start with B and move to C later.

### Recommendation

- Start with B (one party at a time, reset between runs), unless the feasibility test shows C is cheap, in which case build C directly.
- Keep A only for areas with no finish line (a "free roam" cave), if builders want one.

## Resets

- **With B:** restore the dungeon area from its saved state after every run, before the next party. Monsters despawned and respawned from their spawners, traps re-armed, doors closed, chests refilled (for their template, see per-player loot below), great monsters back to full strength. A minute or so; the queue sees "restocking".
- **With C:** nothing to reset; each copy is fresh and thrown away afterwards.
- **What survives a reset (per player, not per dungeon):** loot chest cooldowns (a player who opened a chest today gets nothing from it again until it refills, even in a fresh run), the daily experience cap, the daily finish bonus, lockouts. Kept in mod storage against the player and the adventure.
- **Shuffles:** at each reset (or each copy), choose the random alternatives the builder marked: which chest holds the key, which passage is open, which tribe holds the bridge. Good for replays, but see league tables: shuffles must not make some runs much easier than others (the builder's job; the stats help).
- **After a completion:** the run ends a short time after the finish (for example 2 minutes, to look around and take screenshots), everyone is moved back to the arrival point, and the reset (B) or wipe (C) happens.
- **Builder edits:** the builder edits the template on the land while the adventure is closed, then saves a new **version**. Runs in progress finish on the old version.

## League tables

### What counts as a completion

- A run that reaches the finish the builder marked (the final chest, the boss's death, or a finish plate), on an open adventure, with every member within the level range.
- Recorded for every party member present at the finish, living or ghost (Keir to decide whether ghosts count; suggest yes, they were part of the party).
- Not counted: the builder and their delegates on their own adventure; the admin; guests (no lasting identity); runs where any member had fly, noclip or creative mode (visitors never should in an adventure, but check); runs on an old version once a new one exists (kept, but on that version's table).

### What is recorded

For each completion: adventure and version, the party (names and character levels), party size, time from entering the gate to the finish, deaths during the run, revivals used, date.

### The tables

- **Per adventure:**
  - First completion ("first to clear", kept for ever, per version).
  - Fastest completions, split by party size (solo, 2, 3 to 4, 5 to 6), since a party of six should not compete with a soloist.
  - Fewest deaths (ties broken by time).
  - Most completions by a player.
- **Overall:**
  - Adventurers: number of different adventures completed, then total completions; highest rank.
  - Builders: adventures with the most completions by different players; perhaps a rating from players who finished.
- **Weekly or monthly** versions of the fastest tables, so newcomers have a chance and there is a reason to come back (the all-time tables stay).

### Where they show

- **On the website:** an Adventures page listing each open adventure (name, one-line theme, level range, party size, completions, first to clear) with its tables; each player's completions on their Account page; a link from the map panel of the land. The website is where competition is seen and shared.
- **In the game:** a board at the adventure's arrival point (a block that opens the tables as a form), and a short message to everyone in the game for a first completion ("Thornwatch's Gullet cleared for the first time by ...").
- **On the token card:** the land's card could show "Adventure: The Gullet, completed 37 times". A nice link between the game and the token, and a reason for a holder to build a good adventure.

### Fairness

- Fair tables need every party to start from the same state: B or C, never A.
- Timing starts at the gate, not at the arrival point, so queueing and kit choice do not count.
- Lag in the browser client makes small time differences meaningless; show times to the second, and treat runs within a few seconds as equal (shared rank).
- A builder could quietly make a dungeon easier for friends after they set a record: every save is a new version with its own tables.

## Gear: what you fight with (a question the loot policy raises)

The plan's loot option C keeps loot inside the adventure, so builders' creative-mode items cannot leak into the building world. But then what do visitors fight with, and how do "better weapons and armour" (Keir's point) carry over between adventures?

Proposal: **an adventurer's kit**, a second inventory that exists only in adventures.

- On entering an adventure, the player's normal (building) inventory is put away, as creative mode already does on a holder's own land, and their kit takes its place. On leaving, the kit is put away and the building inventory comes back.
- The kit holds weapons, armour and a few useful items (potions, keys while in a run). It starts with a basic kit (short sword, leather) for new adventurers.
- Loot found in adventures goes into the kit and stays in it, from adventure to adventure. Kit items cannot be placed, dropped or taken out into the building world, so nothing from a creative-mode chest ever reaches the building economy.
- That lets gear progress (better swords, armour found in harder adventures) without the economy problem.
- Builders could hand their friends top gear through loot chests, so: loot chests can only give items up to a tier set by the adventure's level range (a level 1 to 5 adventure offers at most steel; diamond only in high-level adventures), and the best items only from finishing (once per day per player).
- Keys and quest items found in a run vanish when the run ends.
- This replaces loot options B and C in the plan with something better; it fits naturally with the inventory swap code we already have.

## The awkward cases

| Case | Proposed handling |
| --- | --- |
| A player's browser closes or crashes mid-run | They have 5 minutes to come back into the run where they were (downed rules paused); after that they count as having left (no lockout). |
| The whole party disconnects | The run ends after the grace period; the dungeon resets (B) or the copy is wiped (C). |
| The server restarts mid-run | Every run ends; players come back outside with no lockout and no record; copies are wiped at startup. |
| Someone joins the party mid-run | The roster is fixed at the gate. Newcomers wait for the next run (or the builder allows late joining up to the first death; to decide). |
| A member leaves the party mid-run | They are moved back to the arrival point; no lockout; not in any completion. |
| The party splits up inside | Fine; the run continues while any member is inside. |
| A party member idles (away from keyboard) | After 10 minutes without moving they are moved out, so they do not hold a run open. The run's time limit covers the rest. |
| Two parties arrive at once (B) | First at the gate goes in; the other joins the queue. A queue place lasts 10 minutes if the party wanders off. |
| A wiped party wants to try again | Locked out together for the lockout time; they rejoin the queue after it. |
| The builder edits while the adventure is open | Not allowed: close first (runs in progress finish), edit, save a new version, reopen. |
| The land changes hands (token sold) | The adventure belongs to the land: it stays, under its builder's name and tables; the new holder can close, edit (new version) or remove it. |
| A holder removes an adventure | Its tables are kept on the website as "retired", so records are not lost. |
| Monsters leave the dungeon area | Removed at the edge (with B the gate area; with C the copy's walls). |
| Someone tries to dig into the dungeon from outside | Protected (it is on someone's land); with C the copy is beyond reach anyway. |
| Players hurting each other inside | Never inside an adventure. |
| Experience farming by builders | Experience only from monsters that were fighting; daily caps; none for the builder and delegates (see the combat numbers). |
| Deathtraps | Lockouts cost only time in that adventure; death statistics and reports let the admin close bad adventures. |
| Too many runs for the server | Caps on copies (C) and on monsters per run; queue beyond that. |

## What this changes in the plan

- Phase 1 (adventure mode) gains: the dungeon area and its gate, the arrival point outside it, the queue.
- Phase 9 (reset) becomes "runs": restore after each run (B) or copies (C), the run's time limit, the roster, the edge cases above.
- A feasibility test for C (pasting a dungeon into reserved space, spread over steps) should come early, since it decides between B and C.
- League tables and the Adventures page come with the first adventure that has a finish (The Three Bells), so competition starts from day one.
- The adventurer's kit replaces the loot options; it needs Keir's agreement.

## Decisions for Keir

1. Sharing: one party at a time with resets (B), private copies (C), or B first and C later (suggested, unless the test shows C is cheap).
2. Run time limits (suggest the builder chooses 30 to 120 minutes).
3. Whether ghosts count in completions (suggest yes).
4. League tables: which ones at first (suggest per adventure: first to clear, fastest by party size, fewest deaths; overall: adventures completed), weekly versions or not.
5. The adventurer's kit (a separate inventory for adventures, where loot can be kept), and loot tiers by level range.
6. Show completions on the token card (suggest yes).
