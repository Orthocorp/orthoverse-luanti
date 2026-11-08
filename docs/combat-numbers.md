# Combat numbers: a first sketch (8 Nov 2026)

Starting values for the hold-and-release combat, character levels, parties and death rules in [dungeons-plan](dungeons-plan.md). These are a first guess to build and then tune by playing; none of them is shown to players. No code. The model is the SRD 5.2 (CC-BY-4.0): an attack roll against armour class, weapon damage dice, a bonus that grows with level.

## Weapons

Minetest Game has only swords (wood, stone, bronze, steel, mese, diamond) plus tools. Proposal: **the material sets the quality, the kind sets how it fights.** Each kind below in a few materials. New kinds need item pictures (16 x 16), each with a "raised" and a "ready" variant for the wind-up: about three small pictures per weapon kind, a modest art job.

| Kind | Type | Ready after | Full strength at | Tires after | Best range | Reach | Damage (SRD die) | Feel |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Dagger | thrust | 0.1 s | 0.3 s | 1.5 s | 1.5 | 2.5 | d4 | Quick jabs, little gain from holding; strong from behind |
| Short sword | slash | 0.2 s | 0.5 s | 2.0 s | 2.0 | 3.0 | d6 | Forgiving all-rounder; the starter weapon |
| Broadsword (longsword) | slash | 0.4 s | 1.2 s | 2.5 s | 2.5 | 3.5 | d8 (d10 at full strength) | Rewards a full wind-up |
| Bastard sword (two-handed) | slash | 0.6 s | 1.6 s | 3.0 s | 2.5 | 3.5 | 2d6 | Slow, heavy, punishing if mistimed; no shield |
| Spear | thrust | 0.3 s | 0.8 s | 2.5 s | 3.5 | 4.5 | d6 | Keeps monsters at bay; weak up close |
| Mace (a metal ball on a club) | bash | 0.4 s | 1.0 s | 2.5 s | 2.0 | 3.0 | d6, knock-back | Good against heavy armour and armoured parts |
| Morning star (a spiked mace) | bash | 0.5 s | 1.2 s | 2.6 s | 2.0 | 3.0 | d8, knock-back | A heavier mace |
| War hammer (two-handed) | bash | 0.7 s | 1.8 s | 3.0 s | 2.0 | 3.0 | d10, knock-back, short stun at full strength | The armour breaker |
| Axe | slash | 0.4 s | 1.1 s | 2.5 s | 2.0 | 3.0 | d8 | Best at severing parts (great monsters) |

Distances in blocks from the player's eye to the point hit. Inside best range: full effect; between best range and reach: a glance (half damage); beyond reach: a miss.

### How strong a blow is (the hold)

- Released before "ready": a feeble poke (a quarter of the damage, no bonuses).
- Between ready and full strength: rising from half to full damage.
- At full strength, within a short window (the sweet spot, about 0.25 s at character level 1, wider at higher levels): full damage and a bonus to hit.
- Held past "tires after": strength drains back toward half over a second; holding on is never better than releasing at the sweet spot.

### Materials

Decided (8 Nov 2026): no wooden or stone weapons. Every metal weapon gets +1 to hit; the damage rises in equal steps, and bronze is above steel because it is harder to make.

| Material | To hit | Damage |
| --- | --- | --- |
| Steel | +1 | +0 |
| Bronze | +1 | +1 |
| Mese | +1 | +2 |
| Diamond | +1 | +3 |

As built: the dagger, short sword, broadsword, spear, mace, morning star and war hammer, each in these four (28 weapons). Their pictures are painted by tools/weapons/make_weapon_textures.py.

### Weapons and character level

Decided (8 Nov 2026), to build with character levels: any weapon can leave an adventure, be traded, found or crafted, and anyone can carry and use it, but the material's damage bonus only counts up to what the wielder's level allows. A diamond sword in a new player's hand hits like a steel one.

| Material | Damage bonus | Counts in full from level |
| --- | --- | --- |
| Steel | +0 | 1 |
| Bronze | +1 | 3 |
| Mese | +2 | 6 |
| Diamond | +3 | 10 |

Below the level, the weapon gives the bonus of the best material the wielder's level allows (so a level 4 player with a diamond sword gets bronze's +1). The to-hit bonus (+1, any metal) is unaffected. The item's description says "Full strength from level N", so the limit is never a surprise. Crafting recipes for the weapons come at the same time.

Why not forbid using them: a weapon that cannot be swung, with nothing on screen to say why, reads as a bug; capping the bonus keeps every weapon worth finding, trading and keeping for later.

### Nothing shows the sweet spot

Decided (8 Nov 2026): no charge bar or other marker. Players learn each weapon's timing by feel; the weapon in the hand trembles and sags once the arm tires.

## Armour

From 3d_armor if it fits (pieces: helmet, chest, legs, boots, shield). Armour class (AC), as in the SRD, from the total worn:

| Armour | AC | Notes |
| --- | --- | --- |
| None | 10 | |
| Leather (full set) | 11 | Thrust does +1 against it |
| Chain (full set) | 14 | |
| Plate (full set) | 17 | Bash does +2 against it; slash -1 |
| Shield | +2 | Holding it up to block (later) also halves damage from the front, at walking pace |

Monsters have an AC by kind (a rat-folk 11, an orc 13, a stone golem 17) and, if armoured, the same weaknesses.

## Hitting

Decided (9 Nov 2026), after the first fights: getting into position is hard enough, so **a blow that connects always lands**. There is no roll to hit. Instead:

- Armour takes damage off each blow: half a point per point of armour class above 10 (a quarter of a point against bashing weapons). A blow always does at least 1.
- Luck decides only the damage dice, and a critical (1 in 20) doubles them.
- Aim is forgiving: a blow that passes within 20 degrees of a monster, in reach and with nothing solid between, finds it.

| Modifier | Effect |
| --- | --- |
| Released in the sweet spot | +2 damage |
| Head (top of the box) | +50% damage, and a 1 s stun if the blow was at full strength |
| Legs (bottom of the box) | slows the monster for 2 s (not built yet) |
| From the side | +1 damage |
| From behind | +25% damage (daggers +50%) |
| Glance (beyond best range) | half damage |

The sound tells how good a blow was: a swing on every release, then a swish (nothing hit), a light tap (glance), a thud (hit), a heavy thud with a crunch (sweet spot) or a blow with a ring (critical, or a stunning head blow).

With these numbers most monsters fall to one or two good blows; their health goes up when the targets below are tuned.

The earlier plan (a d20 against armour class, with bad-luck smoothing) is dropped: misses on top of the timing and positioning made fights frustrating.

## Character levels (rank)

- Level 1 to 20.
- Character bonus to hit and to AC: the SRD's proficiency bonus: +2 at levels 1 to 4, +3 at 5 to 8, +4 at 9 to 12, +5 at 13 to 16, +6 at 17 to 20.
- Health: Minetest players have 20 health points (10 hearts). Proposal: 20 at level 1, plus 2 per level, so 58 at level 20, shown as hearts scaled to fit (the bar stays 10 hearts; each heart is worth more).
- Damage: + one point per four levels (level 4: +1, level 8: +2, and so on).
- Sweet spot width: 0.25 s at level 1, rising to 0.45 s at level 20.

### The level gap

Monsters have levels too, and the gap matters more than the raw numbers:

| Monster compared to player | Colour | Effect |
| --- | --- | --- |
| 5 or more levels below | grey (trivial) | Player +5 to hit, double damage; monster -5 to hit; no experience |
| 2 to 4 below | green (easy) | Player +2; monster -2 |
| within 1 | yellow (even) | none |
| 2 to 4 above | orange (hard) | Player -2; monster +2 |
| 5 or more above | red (deadly) | Player -5, half damage; monster +5 |

### Level range on entry (Keir's idea)

- Each adventure has a lowest and highest character level allowed in (set by the builder, for example 1 to 5); players outside it cannot enter the adventure's land. Suggested default: the recommended level minus 1 to plus 4.
- A party may enter only if every member is within the range (so a high-level friend cannot carry a party through a beginners' adventure and clear it for everyone).
- Optional later: a "mentor" exception (a high-level player entering a low adventure fights at the adventure's top level, gains nothing, and cannot be the one to finish it).
- With the range in place, the grey and red rows above matter mostly inside the range's edges and for great monsters.

### Experience

- Experience per kill: the monster's base value (by kind and level), times a factor for the gap: grey 0, green 0.5, yellow 1, orange 1.5, red 2.
- Only for monsters that were really fighting: the monster must have attacked or hurt someone in the party in the last few seconds (so a builder cannot make an "experience farm" of trapped high-level monsters that cannot fight back).
- The same spawner again within a day: each further kill from it gives a quarter less, down to nothing.
- A daily cap per adventure per player (about one full run's worth).
- No experience for the builder and their delegates on their own adventure.
- Finishing an adventure (its final chest or boss): a bonus equal to about two even fights' worth per level of the adventure, once per day per adventure.
- Levels: the SRD's experience thresholds are a good shape: level 2 at 300, 3 at 900, 4 at 2,700, 5 at 6,500, 6 at 14,000, 7 at 23,000, 8 at 34,000, 9 at 48,000, 10 at 64,000, rising to 355,000 at 20. Scale the monster values so an evening's play gives a level or two early on and a level every few evenings by the middle ranks. Tune with playtesters.

## Parties

- Experience for a kill is split among living members within 32 blocks, each member's share then multiplied by their own gap factor; the party as a whole gets 10% more per extra member (two players: 110% shared, four: 130%).
- A member 5 or more levels below the monster (red for them) gets at most an "orange" share. (With entry ranges this case is rare.)
- Party size limit: 6.

## Death (revised after Keir's point about deathtraps)

No penalty takes anything lasting away: a builder could otherwise build a deathtrap to drain visitors. The cost of dying is time, in that adventure only.

- Downed: 30 s; a member holding use on them for 3 s raises them with a quarter of their health.
- Dead (not raised in time): solo, back outside the adventure at once; in a party, a ghost until the run ends, then back outside.
- **Lockout:** after dying, the player cannot enter that adventure's land (or lands) for 10 minutes; each further death in the same adventure within 4 hours doubles it (10, 20, 40, then 60 minutes at most); the count clears the next day. A party that wipes is locked out together. Every other adventure and the rest of the world stay open.
- No loss of experience or levels. No weakened spell at first (optional later, if lockouts prove not enough).
- A run's time limit: 2 hours.

## Monsters from the catalogue, rough level bands

| Monster | Band | Notes |
| --- | --- | --- |
| Rats, small spiders, dirt monster | 1 to 3 | first caves |
| Sand and tree monsters, skeleton, orc, gnorm | 2 to 6 | the tribes |
| Stone monster, oerkki, land guard, werewolf, giant ants | 5 to 10 | deeper caves |
| Golem, dungeon master, lava flan, manticore | 8 to 14 | lieutenants |
| Tarantula, kraken, lava titan, dragons | 12 to 20 | bosses until great monsters exist |
| Hydra, giant spider (great monsters) | 10 to 20 | made for parties |

## Testing the numbers

- A test harness that simulates fights (a player of level L with weapon W against monster M at level N, many times) gives win rates and fight lengths before anyone plays; the headless test client used for the game's patches can then run scripted fights in a real world.
- Targets to tune toward: an even one-on-one fight lasts 20 to 40 seconds and a skilled player wins most of the time; a hard fight needs a party or excellent play; a trivial monster dies in one or two blows.
