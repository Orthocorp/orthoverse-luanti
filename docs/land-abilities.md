# Land abilities by castle level

> As built in patch 0061. Adventures (patch 1007) add a use for level 5: a holder of a land at castle level 5 or more can build an adventure on it.

Status 7 Nov 2026 (late evening): abilities spread over levels 1-7 (patch 0061). Nobody but Keir has played yet, so anything can still change until the abilities are announced.

## Rules now (decided 7 Nov 2026)

- Crofts (castle level exactly 0) are common land: any player signed in with an Ethereum wallet, token or not, may mine and build there. Guests cannot build. Pure commons, Minecraft-anarchy style: anyone may dig anyone's blocks.
- Level 8 (level 0 with the futuristic flag) is not a croft: flipping the realm shows the holder takes part. Flipping back to 0 opens it to crofting again.
- On a croft everyone builds with what they carry, holder included: no creative mode there, so creative blocks cannot reach other players.
- The token card shows the land as it really is, mined or not (accepted).
- Rollback recording is on (docker/luanti/orthoverse.conf): admins use /rollback_check and /rollback.
- Castle upgrades keep every 16 x 16 tile anyone has built on (0046), so builds on a croft survive its holder upgrading; the holder can then remove them.

## Abilities by level (as built, patch 0061; LEVELS in mods/orthoverse_creative/init.lua)

| Level (or level + 8) | Gains |
| --- | --- |
| 0 | Croft: common land, no creative mode. Level 8: private, no creative mode |
| 1 | Private building with your own inventory; castle; crest |
| 2 | Creative mode (every block, no damage, own inventory swapped out until you leave) |
| 3 | + fly |
| 4 | + fast; baron's cap |
| 5 | + noclip; coronet |
| 6 | + instant digging with an empty hand (on the land); /goto any land by name, from anywhere |
| 7 | Arrive anywhere you click on the web map; crown |

Fly, fast, noclip, creative and the digging hand apply only while standing on your own land. /goto (level 6) and map arrival (level 7) depend on the highest level among the lands you hold. Admins (teleport privilege) can use both anyway. The castle grows with every level.

Built in 0036/0037: inventory swap, creative item drops destroyed, no reaching onto your land from just off it (dig, build, chests), no fall damage on losing fly, back to the open on losing noclip inside a wall, restore on rejoin, admin (protection_bypass) left alone. Known small gaps, accepted: a boat or cart from the Creative tab can be ridden off the land and picked up as a real item; noclip can carry a player into an open space under or inside another land (they escape with /home; Keir is not worried about unlocked chests).

Testing as admin: `/revoke <name> fly,fast,noclip,creative,protection_bypass`; rejoining restores everything.

## Later abilities (decided 7 Nov 2026 to add separately; levels not yet chosen)

- Delegate: other players who may build on your land
- Welcome message for visitors
- Set the arrival point on your land
- A dedicated henge portal to your land (only 108 henges: "while gateways last")
- Also discussed: builder tools (fill, replace, copy) with volume caps; saved builds usable on your other lands

## Principles agreed

- Before the announcement anything can be tightened. After it, abilities only ever loosen: move down to lower levels or get bigger caps, never removed. Publish that rule.
- Start each ability higher and smaller than seems right.
- Make higher-level extras quantities (sharers, saved builds, tool volume) so higher levels stay ahead when something moves down.
- Experiments as announced, time-limited events.
- Server-protection limits are separate, global, and not a cut to a level's entitlements.
- Avoid anything that presents a token as earning income (paid rent or lending); drop "take items off the land" while blocks have no scarcity.
- Implement one step at a time so Keir can test each.

## Level distribution (lands.json, 1,943 lands)

Level 0: 1,546 (the crofts, common land). Level 8: 39. Levels 1-3 (9-11): about 340. Level 4+ (12+): 37. Level 7/15: 9.
Upgrade price: 0.008 ETH x 2^current level (0 to 1 costs 0.008 ETH; 6 to 7 costs 0.512 ETH).

## Other ideas discussed

- On screen: own land's name in gold with a line under it (level, abilities), the holder's name on other lands, "Exploring as a guest" for guests; maybe particles along your border.
- Admin command to clear a land's built tiles (so its castle upgrades fully).
- Inactive holders: shared building rights, homesteading with buyout, moving lands, a land charter.
- Reach: desktop Luanti and the public server list, selling tokens to Luanti players, OpenSea refresh automation.
