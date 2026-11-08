# Assessment of the adventure ideas (8 Nov 2026)

Keir asked for an assessment of each idea from the evening's discussion. For each: what it adds, how feasible it is in Luanti, how much work, the risks, and a recommendation. Details are in [dungeons-plan](dungeons-plan.md), [adventure-runs](adventure-runs.md), [adventure-design](adventure-design.md), [accounts-plan](accounts-plan.md), [combat-numbers](combat-numbers.md), [builder-workflow](builder-workflow.md) and [monster-catalogue](monster-catalogue.md). No code has been written.

Effort scale: S = one patch, M = two or three, L = several, plus art where noted.

## The big picture first

- **The whole idea is worth doing.** Today the Orthoverse is a world to walk and build in; most lands belong to absent holders, so there is little to do for a visitor. Adventures give non-holders a reason to come and come back, give holders something worth upgrading for, and give the token cards something new to show. It also plays to Luanti's strengths (a block world, easy building, free monsters and wiring mods).
- **The risk is scope.** Together the ideas are a small RPG. Built in order, in playable steps, it is manageable; built all at once, it would stall. The plan below keeps every step playable.
- **Launch first.** None of this should delay the relaunch. The two small fixes found tonight (plain chests open to anyone; players can hurt each other everywhere) should go in before the playtest; the rest after.
- **Who builds adventures?** Few holders are active (37 lands at level 4 or above). The first adventures will be built by Keir and anyone he recruits. Recommendation: let the admin turn on adventure mode on any land (for the samples), and treat builder tools and the builder's guide as part of the work, not extras.
- **Builders cannot be trusted by default.** Anyone at the unlock level can build an adventure, so every rule must hold up against a builder acting in bad faith: deathtraps, experience farms, gear handed to friends, records set on quietly easier versions. This principle (Keir's point about deathtraps) shapes the death, experience, loot and league table rules.
- **One shared world is the hardest constraint.** Two parties in one dungeon spoil each other's run and make league tables meaningless; the answer (one party at a time, or a private copy per party) is in [adventure-runs](adventure-runs.md).
- **Precedent:** the Your Land server (where yl_speak_up comes from) shows a Luanti server with RPG features can work; it may be worth a look for ideas and pitfalls.

## Each idea

### Adventure lands (adventure mode, arrival point, dungeon gate)
- Adds: the frame everything else hangs on; a clear signal to visitors that different rules apply here.
- Feasible: yes, entirely ours, simple.
- Effort: S.
- Risks: few. Decide the unlock level, and let the admin enable it anywhere.
- Recommendation: **do, first.**

### Entry level range (Keir's idea)
- Adds: keeps beginners' adventures for beginners (a high-level player would otherwise clear them in passing) and stops low-level players walking into certain death; lets builders design for a band.
- Feasible: yes; checked wherever a player can arrive on the land.
- Effort: S (with adventure mode).
- Risks: friends of very different levels cannot play together in a narrow band; a "mentor" exception later (the high-level player fights at the band's top level and gains nothing) would solve it.
- Recommendation: **do**, from the start; default range the recommended level minus 1 to plus 4; whole party must fit.

### Sharing a dungeon between parties, and resets (Keir's questions)
- The problem: in one shared world, a second party finds the dungeon half cleared, and can be griefed; resets cannot happen while anyone is inside.
- Options: everyone together (unfair, no league tables); one party at a time with a reset between runs (fair, simple, queues); a private copy of the dungeon per party in a reserved space (fairest, no queues, no resets needed, more machinery).
- Feasible: both B and C reuse the save-and-restore from castle upgrades. C needs copies pasted gradually so the server does not stutter.
- Effort: B is M; C is M to L.
- Recommendation: **start with one party at a time (B)**, and test early how fast a dungeon can be copied; if it is a few seconds, **go straight to private copies (C)**. Full treatment and the awkward cases (disconnects, restarts, idle players, roster changes, land sold) in [adventure-runs](adventure-runs.md).

### League tables (Keir's idea)
- Adds: competition, comparison and a reason to replay; first-to-clear moments worth announcing; a link to the token cards ("completed 37 times").
- Feasible: yes, as long as every party starts from the same state (B or C). Records kept by the game, shown on the website and on a board at the adventure.
- Effort: S to M (recording in the game; an Adventures page on the website).
- Risks: unfair records (handled by fair sharing, separate tables per party size, a new table for each saved version, and excluding builders, delegates and the admin).
- Recommendation: **do**, with the first adventure that has a finish, so competition starts on day one. Start with: first to clear, fastest by party size, fewest deaths, and overall adventures completed; weekly tables later.

### Monsters and spawners (mobs_redo and existing packs)
- Adds: something to fight; the catalogue offers about 150 ready-made monsters, including classic ones (orcs, skeletons, golems, werewolves, spiders, giant ants, dragons).
- Feasible: yes; mobs_redo is mature and well maintained. Our part is limits: spawners only in adventures, monsters kept in the dungeon, caps.
- Effort: M.
- Risks: server load (cap it), quality varies between packs (pick a small set and check each one), no goblins or kobolds ready-made (they would need making).
- Recommendation: **do**, with a hand-picked set of 10 to 15 monsters at first.

### Hold-and-release combat: timing and weapon curves
- Adds: the heart of the "better than mad clicking" goal; makes weapons feel different with no numbers on screen.
- Feasible: yes. The server can see the attack button go down and up, time it, and trace the blow on release. The raised-weapon picture swap works around Luanti's fixed animation.
- Effort: M.
- Risks: feel. It will need several rounds of tuning in play; first versions will feel off. Lag in the browser client argues for generous timing windows.
- Recommendation: **do**, early, and plan time for tuning by playing.

### Aim (head, body, legs; front, side, back) and distance
- Adds: depth: footwork and positioning matter; parties surround monsters; spears and daggers differ.
- Feasible: yes, from the same trace on release. Limited by Luanti giving each monster one box, which is fine for "high, middle, low" and "front or back".
- Effort: S for distance (with the timing patch), S for aim.
- Risks: precision expectations; keep zones generous.
- Recommendation: **do distance with timing; aim right after.**

### Monster wind-up tells
- Adds: the other half of good combat: something to react to, so stepping back is a skill.
- Feasible: yes, but mobs_redo monsters attack in their own way; adding a pause and a sound before the blow means changing how each monster attacks (in our layer, not their code, if possible).
- Effort: M.
- Risks: animation: most pack monsters have no "wind-up" animation, so the tell may have to be a pause, a sound, a particle or a colour flash.
- Recommendation: **do**, with sound and particles as the tell where there is no animation.

### Shields and blocking
- Adds: a defensive choice and a natural party role.
- Feasible: yes (hold the place button with a shield).
- Effort: S.
- Recommendation: **do later**, after the core combat has been played.

### Attack type from the weapon, not the hold
- Assessment: from the weapon is clearer to players and easier to show. Hold time decides strength. **Recommend from the weapon.**

### Hidden dice and armour, SRD 5.2 as the model
- Assessment: right call (Keir's). The SRD gives a tested model to borrow freely (CC-BY-4.0) for the sums, while players only feel "this weapon or armour is better". Credit line needed somewhere on the site.

### Things Keir cut (food, carrying weight, burning torches, the self-drawing map, three attack buttons)
- Assessment: agree with all. Each costs computation or attention and adds little to the fun here.

### Great monsters with parts (giant spider, hydra)
- Adds: the most memorable fights; makes parties necessary; a showcase for the whole system.
- Feasible: yes: parts as small attached hit areas on a body, severed parts hidden by shrinking the model's bone to nothing, behaviour changes per part lost.
- Effort: M in code, plus **significant art** (models with bones and animations for each great monster).
- Risks: art is the bottleneck (Blender work or commissioning); balancing a multi-part fight; hit detection on big monsters (reviewers of NSSM found big monsters hard to hit, which our separate parts would address).
- Recommendation: **do, but last**; start finding or commissioning the hydra model early, because it will take longest.

### Character levels
- Adds: long-term goals, the "easy monsters become trivial" feeling, a reason to return; lets builders grade adventures.
- Feasible: yes, ours, built into the combat sums.
- Effort: S to M.
- Risks: farming by players (no experience from trivial monsters, less from the same spawner); farms built by builders (experience only from monsters that were really fighting, a daily cap per adventure, none for the builder and delegates); confusion with castle levels (call it rank or renown).
- Recommendation: **do**, right after the combat. Keep it earned only, never tied to tokens: that keeps it fair and keeps the tokens from looking like they sell power.

### Parties
- Adds: playing with friends, the main reason people play online games; tougher monsters for groups.
- Feasible: yes; Zughy's Parties mod does forming, invites and party chat, with an API. Our part: following the leader in, health panel, no harm between members, shared experience, the run roster.
- Effort: S to M.
- Risks: AGPL licence of the Parties mod (fine with a public repository and a link to it); big groups flattening adventures (size limit, experience rules, level range).
- Recommendation: **do**, soon after levels.

### Death: downed, ghost, no running back
- Adds: makes death matter in a party; creates the "save my friend" moment; stops a party grinding a boss down by running back.
- Feasible: yes. Luanti lets the server catch death, freeze, hide and disarm a player. The ghost that follows the party needs testing, especially the camera in the browser client; a free-floating ghost limited to the adventure is the fallback.
- Effort: M.
- Risks: complexity for players; keep the rules short and shown on screen ("Downed: a friend can help you up for 30 s").
- Recommendation: **do**: solo rules and the lockout with the first monsters; party rules (downed, ghost) with parties.

### Death penalty (revised after Keir's point about deathtraps)
- Keir's point: any penalty that takes something lasting away (a level, or experience) can be abused by a builder: a deathtrap at the entrance would drain every visitor. So a penalty must cost only time, and only in the adventure where the death happened.
- **Recommended: a lockout** (Keir's proposal). Dying keeps you out of that adventure for a while: 10 minutes for a first death, doubling for further deaths in the same adventure within a few hours, at most an hour, cleared the next day. A wiped party is locked out together, so a boss cannot be worn down by instant retries. Everything else stays open.
- **No loss of experience or levels**, ever. No weakened spell at first.
- Deathtraps themselves: builder statistics (deaths per room) and a "report this adventure" button let the admin close abusive adventures.

### Gear and loot: the adventurer's kit (new, from working through the league tables)
- The problem: creative-mode builders fill the loot chests, so loot that leaves the adventure is free stuff from creative mode; but players should get better weapons and armour over time (Keir).
- Proposal: a second inventory, the adventurer's kit, that exists only in adventures (the building inventory is put away on entry and comes back on leaving, as creative mode already does). Loot goes into the kit and stays there, from adventure to adventure, but can never be placed, dropped or taken into the building world. Loot chests can only give gear up to a tier set by the adventure's level range, and the best only from finishing, once a day.
- Feasible: yes; the inventory swap exists.
- Effort: S to M.
- Recommendation: **do**; it replaces the loot options in the plan (gear progresses, the building economy stays clean).

### Loot chests
- Adds: reward; Treasure Chest already gives every player their own fill on a timer, so no squabbling in parties.
- Feasible: yes, mostly existing.
- Effort: S.
- Recommendation: **do**, filling the adventurer's kit, with tiers by level range.

### Mesecons (traps, secret doors, puzzles)
- Adds: set pieces, puzzles, secret routes; a whole adventure style (the funhouse) with no new art.
- Feasible: yes; pistons already respect protection, so mostly configuration.
- Effort: S.
- Risks: server load from big contraptions (Mesecons has overheat protection; add limits if needed); leave out the programmable controllers; deathtraps (see the death penalty).
- Recommendation: **do, early**: it makes the first sample adventure possible before any combat work.

### Builder tools (WorldEdit limited to your land)
- Adds: makes building a large adventure realistic.
- Feasible: yes, a thin layer of ours over WorldEdit.
- Effort: S to M.
- Risks: large edits loading the server (volume caps).
- Recommendation: **do**, before asking anyone else to build adventures.

### Rune magic
- Adds: a second way to play (support, ranged), fire for the hydra, healing and rare resurrection for parties.
- Feasible: yes, a small rune bag interface plus spell effects.
- Effort: M.
- Recommendation: **later**, once combat feels right. Keep it small: a handful of spells; runes live in the adventurer's kit.

### Characters to talk to and quests
- Assessment: dropped (Keir finds them annoying). Agree for the samples: places and signs tell the story. Keep yl_speak_up in mind only if other builders ask.

### Password accounts, linking a wallet later
- Adds: the biggest accessibility gain of all the ideas: people without a wallet get a real character that keeps progress (and appears in league tables); a path to linking a wallet later grows the holder base.
- Feasible: yes. Keep the auth service as the only door: it checks the password, then hands the play page the derived game password as it does for wallets, so the game hardly changes.
- Effort: M (auth service and pages).
- Risks: throwaway accounts and griefing (registration limits, Cloudflare Turnstile, croft building only after some play); lost passwords (a recovery code, or the linked wallet).
- Recommendation: **do, before or with the playtest**; it helps more than any adventure feature, and adventures and league tables need persistent characters anyway.

### Sample adventures built on what makes modules popular
- Assessment: the research points to: a safe home base with a choice of places, rival factions, one great boss, a clear one-line theme, set-piece rooms, non-linear maps with loops and secrets, something to collect, replayability by shuffling, and a gentle start. All translate to the Orthoverse; story-heavy and talk-heavy adventures do not.
- Recommendation: ship four samples, in this order: **The Three Bells** (puzzle tower; needs no monsters), **The Gullet** (ravine of rival tribes below a fort), **The Fallen Star** (crashed starship for the futuristic realm), **The Drowned Pit** (the hydra).

## Suggested order (milestones, each playable)

0. **Before the playtest:** plain-chest fix; players cannot hurt each other (or only where chosen); password accounts (if Keir agrees).
1. **The Three Bells:** adventure mode, arrival point, dungeon gate and level range, one party at a time with a reset after each run (or private copies, if the early test shows they are cheap), Mesecons, loot chests and the adventurer's kit, the death lockout, league tables and the Adventures page. First sample adventure live, with competition from day one.
2. **The Gullet:** monsters and spawners (a chosen set), hold-and-release combat with distance, character levels (with the anti-farm rules), rival factions. Second sample live.
3. **Better fights:** aim zones, monster wind-up tells, parties with the downed and ghost rules, shields.
4. **Builders:** WorldEdit on your own land, delegate, a builder's guide page, builder statistics and reporting; invite holders to build.
5. **The Fallen Star:** robot monsters (models), futuristic set pieces. Private copies, if not already built.
6. **Great monsters and The Drowned Pit:** the hydra (model commissioned during milestones 2 to 4), then the giant spider.
7. **Later:** rune magic; more monsters; a party-finding board; weekly league tables; completions on the token cards.

## Open questions that block early milestones

- Unlock level for adventure mode (suggest 5, and the admin anywhere).
- Players hurting each other (suggest off everywhere for now).
- Password accounts: yes, and croft rules for them.
- Sharing: one party at a time first, or private copies (suggest B first, with an early test of C).
- The adventurer's kit (suggest yes; it replaces the earlier loot options).
- Lockout lengths (suggest 10 minutes doubling to an hour).
- League tables at launch (suggest first to clear, fastest by party size, fewest deaths, adventures completed).
