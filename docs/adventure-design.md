# Adventure design: what makes D&D modules popular, and sample adventures for the Orthoverse

> Status: none of the four sample adventures is built yet. The Three Bells is next: it fits on one land (dungeon area about 60 x 60 x 50: a belfry about 15 x 15 rising 40 to 50 blocks, three wings of three or four puzzle rooms of about 9 x 9 x 6, and an entrance courtyard outside the area).

Draft, 8 Nov 2026 (night). Keir asked: which D&D modules exist, which are most popular, and what features make them popular, so the game can ship better sample adventures. Research notes, then what translates to a Luanti world, then original sample adventures. Companion to [dungeons-plan](dungeons-plan.md). No code.

All sample adventures here are original: they borrow structures and design ideas (which anyone may use), never names, maps or text from published modules.

## The modules people rate and buy

### The classics (Dungeon magazine's 30 greatest adventures, issue 116, 2004)

The top ten: Queen of the Spiders (G1-3, D1-3, Q1), Ravenloft (I6), Tomb of Horrors (S1), The Temple of Elemental Evil (T1-4), Expedition to the Barrier Peaks (S3), Desert of Desolation (I3-5), The Keep on the Borderlands (B1), Return to the Temple of Elemental Evil, White Plume Mountain (S2), Return to the Tomb of Horrors. Others on the list include The Forge of Fury, Isle of Dread (X1), Castle Amber (X2), Against the Cult of the Reptile God (N1), Ruins of Undermountain, The Sinister Secret of Saltmarsh (U1), The Lost City (B4), Dark Tower and The Ghost Tower of Inverness.

### Since 1985 (DMDavid's ten greatest)

Night's Dark Terror, Red Hand of Doom, Lost Mine of Phandelver, Curse of Strahd, Dead Gods, Madness at Gardmore Abbey, Vault of the Dracolich, Sunless Citadel, Tomb of Annihilation, The Gates of Firestorm Peak.

### Best sellers of 5th edition (BookScan figures, Alphastream, 2023)

Curse of Strahd first (about 147,000 copies), then Waterdeep: Dragon Heist, with Hoard of the Dragon Queen, Tales from the Yawning Portal and Ghosts of Saltmarsh making up the top five. Three of the top five are reworked classics and two are anthologies of shorter adventures. Clearly themed releases last; high-level adventures (Dungeon of the Mad Mage) sell briefly and then stop.

### What reviewers say works (Sly Flourish's guide to the 5e adventures)

The most recommended are short and clear: the starter adventures (Dragons of Stormwreck Isle, Dragon of Icespire Peak with its job board of quests from one town, Lost Mine of Phandelver). Recurring praise: a home base with a choice of places to go, a clear motivation, a persistent villain (Strahd), locations with character. Recurring complaints: low-level monsters that kill new characters, instant-death traps, no clear reason to go anywhere, villains with no link to the main story, sprawling scope that is hard to run.

## The features behind the popular ones

| Feature | Modules that show it | Why it works |
| --- | --- | --- |
| A safe home base and a choice of places to go | Keep on the Borderlands (the keep, then the Caves of Chaos), Lost Mine of Phandelver (Phandalin), Dragon of Icespire Peak (the job board) | Players pick their own order and difficulty; there is somewhere to retreat to; the place gets familiar |
| Rival factions in one place | Keep on the Borderlands (tribes in neighbouring caves), Temple of Elemental Evil (the elemental cults) | The dungeon feels alive; players can turn monsters against each other; the same caves play differently each time |
| One memorable villain or boss, felt throughout | Ravenloft and Curse of Strahd, the dragon at the bottom of The Forge of Fury and Sunless Citadel | A goal and a story without much text; a climax everyone remembers |
| A strong single theme | Curse of Strahd (gothic horror), Rime of the Frostmaiden (isolation), Barrier Peaks (a crashed starship in a fantasy world) | Easy to describe in one line; easy to want to play |
| Set-piece rooms, puzzles and traps | White Plume Mountain (a "funhouse" of puzzle rooms guarding three famous weapons), Tomb of Horrors (deadly traps that reward thinking) | Things to talk about afterwards; variety beyond fights |
| Non-linear maps: loops, several ways in and down, secret routes ("Jaquaying the dungeon", after designer Jennell Jaquays' Caverns of Thracia and Dark Tower, as described by Justin Alexander) | Caverns of Thracia, Dark Tower, Keep on the Borderlands' interlinked caves | Players make real choices; retreat and outflanking are possible; every group's run is different |
| A twist | Sinister Secret of Saltmarsh (the haunted house is a smugglers' front), Gates of Firestorm Peak (a dungeon crawl that turns into Lovecraftian horror) | Rewards attention; worth retelling |
| Something to collect across the adventure | White Plume Mountain (three weapons), Madness at Gardmore Abbey (scattered cards of a Deck of Many Things) | A thread through scattered places; a natural trophy |
| Replayability by chance | Ravenloft (a card reading decides where key items and the villain's lair are) | Different each time, even for the same players |
| Several groups in one dungeon at once | Vault of the Dracolich (several tables explore different parts of one dungeon, trade and meet for a final battle) | Exactly our situation: one shared world with several parties |
| Gentle start | The starter sets | New players are not killed in the first room |
| Reputation for deadliness | Tomb of Horrors | A challenge people seek out, as long as it is opt-in and known |

## What translates to the Orthoverse

Strong fits:
- **Home base plus sites:** the arrival point as a safe keep or camp, with the dungeon sites around it on the same land or the holder's neighbouring lands.
- **Rival factions without talking:** Keir dislikes talking to monsters, and factions do not need it. Monsters of rival tribes can fight each other when they meet (mobs_redo lets a monster attack chosen other kinds; to verify). Players can lure one tribe into another, or wait while they weaken each other. The faction story is told by the place: banners, bones, barricades between the caves.
- **One great boss:** the great monsters with parts (the hydra, the giant spider) are exactly the memorable climax these modules have.
- **Set-piece rooms with Mesecons:** pressure plates, sliding walls, timed doors, rooms that flood (water), the funhouse style needs few monsters and no new art.
- **Non-linear maps:** a voxel world makes loops, secret passages and several ways down easy and natural; a builder's guide can teach the Jaquays principles in a page.
- **Collect-the-set:** three relics guarded by three sites, each relic a trophy (loot option C).
- **Replayability by chance:** at each reset, shuffle which site holds which relic, which side passage is open, which tribe holds the bridge. Cheap to do with the reset system.
- **Several parties at once:** Vault of the Dracolich shows it can be a feature: separate wings for separate parties, meeting at the end.
- **Theme in one line:** each sample adventure should be sayable in a sentence on the map panel.
- **The futuristic realm:** Barrier Peaks (a starship in a fantasy world) is a natural model for the Orthoverse's futuristic flag (levels 8 to 15): a fallen starship on a fantasy land.

Weaker fits:
- Story-heavy, dialogue-heavy or investigation adventures (Dragon Heist, Dead Gods): they rely on talking and a game master.
- Instant-death traps: frustrating in a real-time game with lag; use heavy damage and visible warnings instead, and keep true deadliness for an opt-in "hard" adventure.
- Huge sprawling campaigns: too much to build and too much to explain.

## Lessons for builders (a page for the builder's guide)

1. Say the theme in one line, and put it on the entrance sign.
2. Give a safe start: the arrival point is a place to gather, shop or rest, not a fight.
3. Offer choices: at least two ways forward from the start, loops, and one secret route.
4. Grade the danger: easy near the entrance, harder deeper in, the boss last; show the recommended level and party size at the entrance.
5. Put rivals next to each other and let them fight.
6. Build one set-piece room per site: a trap, a puzzle, a dramatic view.
7. End with one boss worth remembering.
8. Give a reason to finish: a relic, a trophy, a view from the top.
9. Shuffle something on every reset.
10. Warn before you kill: a sound, a crack in the floor, a scorched wall before the fire trap.

## Sample adventures to ship with the game (original)

Four, to cover the main styles and show builders what is possible. Names are placeholders.

### 1. The Gullet (home base and rival caves; the Keep on the Borderlands structure)

- One line: "Six tribes dig into the walls of a ravine below Thornwatch fort. Clear them, or let them clear each other."
- Thornwatch, a small fort at the ravine mouth, is the arrival point: safe, with a smithy (weapon swap), a shrine (where revival items work), a notice board of what is known about each cave.
- Six caves up both walls of the ravine, graded by level: rat-folk near the mouth, then two rival tribes facing each other across the ravine floor (their skirmishes are visible), then a stone-golem workshop, then the spider nest, then a temple at the head of the ravine with its keeper (the boss).
- Caves connect by tunnels the tribes have dug into each other's caves; one cave connects to the temple by a secret route.
- Shuffled on reset: which tribe holds the rope bridge across the ravine, and which cave the temple key is in.
- Size: one or two lands. Party size two to four, levels 1 to 5.
- Needs: monsters from the existing packs, rival factions, Mesecons for the temple, loot chests, the reset.

### 2. The Three Bells (funhouse puzzle rooms; the White Plume Mountain structure)

- One line: "A mad bellfounder hid three bells in his tower. Each room is a trap he built for thieves."
- Few monsters; each room is a puzzle built from Mesecons: a floor that drops if you step on the wrong tiles, a room that fills with water until a lever is found, a corridor of pistons with a rhythm to learn, a mirror maze, a room where the door only opens while someone stands on a plate on the other side (needs two players, or a block pushed onto it).
- Three bells at the ends of three wings; ring all three in the belfry to open the founder's vault.
- Shuffled on reset: the order of the pressure-plate tiles, which wing holds which bell.
- Size: one land. Solo or party, any level (it is about puzzles).
- Needs: Mesecons, loot chests, the reset. No new monster art at all: a good first adventure to build, even before the combat work.

### 3. The Drowned Pit (one great monster; the boss-lair structure)

- One line: "Something with too many heads lives at the bottom of the old quarry."
- A short descent through a flooded quarry with a few lesser monsters, to a great pit where the hydra rises from the water. Braziers around the rim give fire for burning stumps; a collapsing walkway changes the fight halfway.
- Size: one land. Party of three to five, high level.
- Needs: the great monster with parts (the hydra), the party and death rules. The showcase adventure for the combat system; the last of the four to build.

### 4. The Fallen Star (genre mash for the futuristic realm; the Expedition to the Barrier Peaks structure)

- One line: "A ship from the futuristic realm crashed into the hills. Its machines are still running."
- On a futuristic-flag land: a crashed starship half buried in a fantasy hillside, corridors of tarmac and glass (the futuristic realm's style), maintenance robots that attack, sealed doors opened by keycards found inside (Mesecons and keys), a reactor room as the set piece.
- Size: one land. Party of two to four, mid level.
- Needs: robot-like monsters (the catalogue has golems and stone monsters as stand-ins; proper robots need models), Mesecons, futuristic blocks already in the game.
- A good way to show the futuristic flag is more than a look.

### Order

The Three Bells first (no new art, shows Mesecons and puzzles, needs only adventure mode, Mesecons, loot and reset), then The Gullet (monsters, combat, levels, factions), then The Fallen Star, then The Drowned Pit (great monsters).

## Sources

- Dungeon magazine's 30 greatest adventures (issue 116, 2004), reproduced by Grognardia: https://grognardia.blogspot.com/2008/09/30-greatest-d-adventures-of-all-time.html
- DMDavid, the 10 greatest D&D adventures since 1985: https://dmdavid.com/tag/the-10-greatest-dungeons-dragons-adventures-since-1985/
- Alphastream, D&D 5e's top-selling adventures: https://alphastream.org/index.php/2023/09/29/dd-5es-top-selling-adventures-and-what-it-means-for-the-hobby/
- Sly Flourish, guide to published adventures: https://slyflourish.com/guide_to_published_adventures.html
- Justin Alexander, Jaquaying the dungeon: https://thealexandrian.net/wordpress/13085/roleplaying-games/jaquaying-the-dungeon
