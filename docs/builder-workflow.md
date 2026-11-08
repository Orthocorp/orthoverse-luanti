# Building an adventure: the holder's workflow (sketch, 8 Nov 2026)

> **Sketch written before the build.** What exists today is described in [adventures.md](adventures.md): the commands differ (corner1 and corner2 for the area, start and arrival, save and open), and monsters, loot, shuffles, test mode and joined lands are still to come.

How a holder (or Keir, for the sample adventures) would make an adventure once the pieces in [dungeons-plan](dungeons-plan.md) exist. Written from the builder's side, to check the plan hangs together and to become the in-game and website guide. No code.

## 1. Choose the land and turn on adventure mode

- On your land (castle level 5 or more, to be decided; the admin anywhere): `/adventure on`. The land line at the bottom left now reads "Adventure"; visitors see it on the map panel too.
- While building, close it to visitors: `/adventure closed` (visitors arriving are told it is being built). `/adventure open` when ready.
- Several neighbouring lands you hold can form one adventure (`/adventure join <land>`), for big ones such as The Gullet.

## 2. Set the scene

- `/arrival` where you stand: where visitors arrive and come back after dying. Make it a safe place (a fort, a camp, a shrine).
- `/adventure name "The Gullet"` and `/adventure line "Six tribes dig into the walls of a ravine..."`: the one-line theme shown on arrival and on the map.
- `/adventure level 1-5` and `/adventure party 2-4`: the recommended character level and party size, shown at the entrance and on the map.

## 3. Build

- In creative mode on your land, as now, with builder tools (fill, copy, saved builds) on your own land when that phase exists, and friends helping via delegate.
- Follow the builder's guide (the ten lessons in [adventure-design](adventure-design.md)): a safe start, choices and loops, graded danger, rivals side by side, a set piece per area, one boss, a reason to finish, a warning before every deadly thing.

## 4. Add monsters

- Place spawners (creative mode, adventure lands only). Each spawner's form: monster kind (from the game's chosen set), level (within the kind's band), how many alive at once, respawn delay (or "once per reset"), radius, wake when a player comes near, and faction (which other spawners' monsters it fights).
- The land's monster cap is shown in the form ("23 of 40 used").
- Great monsters (hydra, giant spider) from a special spawner, one per adventure, in a room big enough (the form checks the space).

## 5. Add traps, doors and puzzles

- Mesecons parts from the creative inventory: plates, levers, pistons, sliding walls, detectors, lamps, noteblocks.
- Level-gated doors (only open for players of a set rank) for deeper parts.
- Keys: locked doors with keys that loot chests hand out.

## 6. Add loot

- Loot chests: fill the template in creative mode, set the chance per slot and the refill time ("once per reset", "every 24 h"). Every visitor gets their own.
- Mark the final chest (or the boss) as the finish: it gives the trophy and the finishing experience bonus.
- Remember: loot stays in the adventure (if option C is chosen); only the trophy leaves.

## 7. Save the adventure

- `/adventure save`: stores the adventure as it is (blocks, doors, chests, spawners, wiring) as the state every reset returns to.
- Shuffles: mark alternatives that the reset chooses between at random: "one of these three chests holds the key", "one of these two passages is open". (A shuffle marker block, or a form on the chest or door.)
- `/adventure reset` to test the reset yourself.

## 8. Test

- `/adventure test`: play it as a visitor would: creative mode off, your own inventory put away, a test character at the recommended level (so the holder can check the difficulty), and nothing you do counts toward your real character.
- Leave test mode and fix what you found; save again.

## 9. Open it

- `/adventure open`. It appears on the website's map with its name, line, level and party size, and on an "Adventures" list on the site (new page, later).
- Statistics for the builder: visits, finishes, deaths per room (where players die most), average time. Helps tune difficulty.

## 10. Keep it going

- Automatic resets when empty; `/adventure reset` any time nobody is inside.
- Edit any time: close it, change things in creative mode, save again, reopen.

## What this needs that is not yet in the plan

- Several lands as one adventure (`/adventure join`).
- A closed state while building.
- The test mode with a temporary character at a chosen level.
- Shuffle markers.
- Builder statistics (deaths per room in particular).
- An Adventures list on the website.

These are small to medium additions to phases 1 (adventure mode), 9 (reset) and the website; worth adding when those phases are built.
