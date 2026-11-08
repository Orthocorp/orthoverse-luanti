# Adventure decisions (8 Nov 2026)

Keir accepted every suggested answer to the 39 open questions (8 Nov 2026, 01:11). Work happens on the git branch **adventure**, patches numbered from **1001**. The playtest items go on that branch too.

## Progress on the branch (8 Nov 2026)

- 1001: chests and other inventories follow land protection; enable_pvp = false.
- 1002 to 1004: password characters (auth service with scrypt hashes, recovery code, wallet linking, Turnstile optional; site sign-in panel and Account page; game: they join, and build on crofts after an hour of play). Admin tool web/auth/recovery-code.js.
- 1005: no sideways scroll bar in the sign-in panel.
- 1006: WorldEdit (admin only, worldedit privilege) and Mesecons (dungeon set, no controllers or gates; mesecon.mvps_protection_mode = normal).
- 1007: mods/orthoverse_adventure: /adventure, gate, finish and board blocks, one party at a time with restore after each run, records per version, adventures.json for the website.
- 1008: the Adventures page (/adventures/) and /api/adventures.
- 1009: home page text for password characters and the everyman's right.
- 1010: the site's pages always fresh (no-cache), so new links show at once.
- 1011: /adventure help in a window, rewritten steps; a player told when a completion is not recorded (builder, admin, guest).
- 1012: fonts in the browser game: Alegreya for text, Midnight for titles and buttons.
- 1013: the browser game build builds Emscripten's ports in their own layer (a failed SDL2 download had stopped the engine build).
- 1014: these documents in docs/.

What exists now is described in [adventures.md](adventures.md).

Finding (copy timing test, 8 Nov, sandbox with 2 cores): copying a whole land's volume (96 x 192 x 96) with VoxelManip takes about 230 ms in one go, or about 11 ms per 16-layer slice. Private copies (option C) are therefore cheap enough to build when wanted; the restore after each run uses the same slice-per-step method.

## Before the playtest
1. Players cannot hurt each other anywhere.
2. Plain chests on private lands open only for the holder.
3. Password characters: yes, before the playtest.
4. Password characters build on crofts only after an hour of play or reaching rank 2.
5. Lost passwords: a recovery code shown once (or the linked wallet).
6. Cloudflare Turnstile on registration (optional: works without keys).
7. Guests stay alongside password characters.

## Milestone 1 (The Three Bells)
8. Slim milestone 1: adventure mode, gate, Mesecons, a finish, one party at a time with a reset after each run, a completions list.
9. Adventure mode from castle level 5; the admin anywhere.
10. One party at a time first; private copies later if queues appear; an early timing test of copying.
11. Run time limit chosen by the builder, 30 to 120 minutes.
12. Mesecons: the dungeon set, without the programmable controllers and the command block.
13. Guests: puzzle adventures only; combat adventures need a character.
14. WorldEdit for the admin now.
15. League tables first: who completed each adventure and the fastest; more tables later.
16. Completions on the token card: yes, later.

## Milestone 2 (combat, The Gullet)
17. Five experiments before combat (browser client with monsters, holding the button, hooking mobs_redo, copying a dungeon, ghosts).
18. Attack type from the weapon.
19. Head hit: +50% damage and a 1 s stun at full strength; from behind: +3 to hit, +25% damage.
20. Higher rank widens the sweet spot.
21. The character level is called **rank**.
22. Rank cap 20.
23. Entry range by default: recommended rank -1 to +4; every party member must fit.
24. The adventurer's kit, with loot tiers by level range.
25. Monster drops only through loot chests, into the kit.
26. Lockout after dying: 10 minutes, doubling to an hour within a few hours, cleared the next day.
27. No monsters in the wild.
28. An "easy timing" option with assisted records: later.

Added 8 Nov 2026: any weapon may leave an adventure, be traded, found or crafted; its material's damage bonus counts only from a rank (steel 1, bronze 3, mese 6, diamond 10), and its description says so. See combat-numbers.md.

Built on 9 Nov 2026 (patches 1033 to 1036, decided by Claude while Keir was away, as he asked):
- Blows that connect always land; armour takes damage off instead (Keir: missing on top of positioning was too hard). A forgiving 20-degree aim. Sounds for each kind of blow.
- Rank and experience as in combat-numbers.md (decisions 20 to 22 and the experience rules).
- The adventurer's kit (decision 24) is dropped: weapons are ordinary items, made or found; loot chests fill from our tables, never from a builder's creative inventory, capped by the adventure's top rank; a metal counts in full only from a rank. That keeps gear fair without a second inventory.
- Death in a run: the lockout (decision 26), and nothing is lost (inventory kept, not left in bones), back at the entrance.
- Entry ranges (decision 23): set by /adventure ranks; each player is checked at the gate, so every member of a party fits.
- The Gullet, scaled to one land and the monsters there are, with an orc warlord as its boss.

## Milestone 3 and later
29. Our own small party module (not the AGPL Parties mod).
30. Party size 6; +10% experience per extra member.
31. Level-gated doors: every party member must qualify.
32. Ghosts share in completions and trophies.
33. Revival items: rare, the builder's choice.
34. Up to two checkpoints per adventure.
35. Hired companions for solo players.
36. "One party at a time" option only matters if private copies are built.
37. The hydra first; find or commission its model early.
38. A mentor exception to the level range: maybe, once there are enough players.

## Not code
39. Find a second admin before launch.
