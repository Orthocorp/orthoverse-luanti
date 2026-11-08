# Ready-made adventures

Each adventure here is two files:

- `<name>.we`: its buildings, as a WorldEdit file.
- `<name>.json`: where things are in it. This covers its size, the ground layer, the underground parts to dig out, the dungeon area's corners, the start, the arrival, the name, the one-line description and the time limit.

The server image copies this folder into the game, so after a `git pull` and `docker compose up -d --build luanti` the admin can place one with `/adventure place`.

## Placing one

1. Go to the land that should hold it. The land must have no adventure yet; use `/adventure delete` first if it has one.
2. Stand on the ground at the **south-west corner** of where it should go. It extends east and north from there, and must fit on the land. The game says so if it doesn't.
3. Type `/adventure place three-bells`. On its own, `/adventure place` lists the adventures in this folder.

The command does the following:
- It clears everything above the ground over the whole footprint.
- It digs out the underground parts.
- It fills any dips under the floor with dirt.
- It builds the adventure.
- It makes it the land's adventure, with the area, start, arrival, name, line and time limit already set.

The adventure is left **closed and unsaved**. Look round, change what you like, then run `/adventure save` and `/adventure open`.

Placing is for the admin only, because it changes a large area at once.

The file also works with plain WorldEdit (`//load three-bells` after copying it to the world's `schems/` folder), but then nothing is cleared or set up for you.

## The Three Bells

*A mad bellfounder hid three bells in his tower. Each room is a trap he built for thieves.*

It needs 60 blocks east by 42 north. The buildings rise 38 blocks above the ground; the crypt, the pit and the well go up to 8 below it. The ground floor is at the height you stood at when you placed it.

```
          north
   +----------------------------------------------------------+
   |        crypt (below): Two Plates | silver rope            |
   | Sunken Lever  iron rope [ TOWER ] bronze rope   Ceiling  |
   | Stepping St.  Grate  [ hub + stairs down ] Library  Maze |
   |                 [ courtyard, gate, board ]                |
   +----------------------------------------------------------+
          south (where you stood: south-west corner)
```

### The route

- **Courtyard** (outside the dungeon area): the gate, the records board and a sign. The way into the building is barred, so players enter through the gate. The arrival point is here.
- **Hub**: the start. Exits west, east and north (to the tower), plus stairs down to the crypt in the north-east corner.
- **West wing:**
  - **The Grate** (puzzle).
  - Its steel door leads to **the Stepping Stones**, then **the Sunken Lever**.
  - Then the **iron bell's rope**.
- **East wing:**
  - **The Library** (puzzle).
  - Its steel door leads to **the Dark Maze**, then **the Ceiling**.
  - Then the **bronze bell's rope**.
- **Crypt:**
  - **The Four Levers** (puzzle).
  - Its steel door leads to **the Two Plates**.
  - Then the **silver bell's rope**.
- **Tower:** three steel doors stand in a ring around a central stair.
  - Each rope opens one of them.
  - Through all three, the stair winds up to the belfry, where the three bells hang and the **finish** stands.

### The puzzles (solutions)

- **The Grate.** A slot in the north wall, three blocks wide, is too low for a player to climb through: a half slab and one block high. Beyond it, six pressure plates sit in an alcove. The steel door opens while something lies on a plate. The solution: punch the **pile of pebbles** in the corner for a pebble, stand right at the slot looking straight through it (or slightly up) and drop the pebble (the drop key, Q by default). From further back it hits the wall. Pebbles drop for real even in creative mode, so you can test it while building.
- **The Library.** Four levers hang among the bookshelves, and only one works. The sign says "my own book lies beneath my golden name": it's the lever under the gold block.
- **The Four Levers.** The levers on the east wall open the door only when set high, low, high, low (first and third pulled, second and fourth left down), as the sign says. Any other setting closes it again. The logic sits behind the wall: two Mesecons torches and a wire.
- **The Stepping Stones.** A pit of water fills the room. Stone pillars rise from it, each level with the last or one higher, with a block's gap between. They lead to a way out high in the north wall. Whoever falls in climbs the ladder back to where they came in.
- **The Sunken Lever.** A well, four deep, in the floor. The lever that opens the door to the iron bell's rope is at the bottom: swim down and pull it.
- **The Dark Maze.** No lamps, only a few fireflies. High walls make a maze from the Library's door to a way out in the far north-east corner. Following one wall gets you through.
- **The Ceiling.** Four levers on the north wall. Above them the ceiling shows the setting: gold for high, obsidian for low. The solution is low, high, high, low. The logic lies under the floor.
- **The Two Plates.** Two slots in the south wall, each with pressure plates beyond. The door opens only while both bear weight: throw a pebble through each slot (the pile is in the room).
- **The ropes.** Pulling the lever in each rope room opens its door in the tower. A door stays open as long as its lever stays pulled.

All the doors are steel doors that no player can open by hand: only the wiring opens them. All the wiring runs under walls and floors. Wires for the silver rope also climb through the crypt's north wall (the rod beside its lever).

After every run the whole dungeon goes back to its saved state: levers down, doors shut, pebbles gone.

Each puzzle is checked by the generator (tools/adventures/): its door is shut at the start and opens when the puzzle is solved, and wrong settings shut it again. The Stepping Stones has no wiring and is checked by eye only: try the jumps.

### Changing it

Nothing is left to build: every room has its puzzle. You can change any room before saving.

Wiring tips, as used here:
- A **wall lever** powers the block under the block it hangs on.
- A **wire** there climbs to a door standing diagonally above it.
- A **pressure plate** powers the blocks diagonally below it.
- A **Mesecons torch** turns off while the block two behind it (through the block it stands on) is powered.
- Keep separate wires two blocks apart, or they join.

### Then

Run `/adventure save`, then `/adventure open`. Test with a second character: your own runs aren't recorded.
