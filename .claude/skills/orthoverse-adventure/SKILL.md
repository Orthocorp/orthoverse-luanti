---
name: orthoverse-adventure
description: Write a ready-made Orthoverse adventure (a generator script, its .json and its .we or .ovt template) from a description of the place, its puzzles, monsters and plot, tested and delivered as patches for review. Use when asked to make, extend or fix one of the game's ready-made adventures.
---

# Making a ready-made Orthoverse adventure

The Orthoverse is a Luanti (5.18) game on Minetest Game. Its ready-made
adventures (The Three Bells, The Gullet, The Fallen Star, The Mill at Withy
Ford, St Morwen's, The Wyrm Below, Tir Na Nog, The Seed) are not built by hand:
each is a Lua script that builds it block by block, run on a local server that
saves it as a template and checks it. The admin places a template on a land
with `/adventure place <name>`.

You are given a description: what the place is, its theme, suggestions for
puzzles, monsters or plot. You turn it into:
- `tools/adventures/<name>.lua`: the builder;
- `adventures/<name>.json`: the template's settings (written by the generator);
- `adventures/<name>.we` (WorldEdit form) or `adventures/<name>.ovt` (the
  compact form, for anything big: a palette and a compressed grid of every
  block, written in one fast write; The Wyrm Below's 512,000 blocks are 46 KB);
- and, when it needs new blocks, items or monsters, the mod code, textures
  and sounds for them.

Read these first, in the repository:
- `tools/adventures/README.md`: how each adventure is generated and checked;
- `tools/adventures/generate_adventure/init.lua`: the generator and its checks;
- one builder close to what you are making, as the pattern to follow:
  `wyrm_below.lua` (big, underground, compact form), `seed.lua` (surface and
  underground, its own extra checks), `st_morwens.lua` (surface, buildings),
  `fallen_star.lua` (sci-fi, keycards);
- `docs/adventures.md`: how adventures work in the game, and every block,
  item and fitting the mods offer;
- `adventures/README.md`: how each one is placed, and what it says to players.

## How an adventure works in the game (the rules it must fit)

- An adventure is a box (`corner1` to `corner2`) on one land. Players reach it
  through a **gate** outside the box: going through starts a **run** and puts
  them at the **start** inside. Whoever goes through within 60 s of the first
  joins the party, up to 6. One party at a time.
- A run ends at the **finish** (a finish block, touched), when everyone has
  left or died, or at the **time limit**. Then the whole box is **restored**
  from the saved template: everything a run changed (doors opened, blocks
  moved, monsters killed) is put back. Design freely for that.
- Inside, players carry only the **kit** (default: a steel short sword and a
  healing draught) plus what they find; their own inventory waits outside.
  Only gold and gems leave the adventure.
- **Ranks** (`rank_min`, `rank_max`) say who may enter. Dying locks a player
  out of that adventure for a while; nothing else is lost.
- Inside the box nobody digs or builds (it is protected); throwing things out
  of a run is blocked (they fall at the thrower's feet; pebbles excepted).
- Monsters come only from **spawners**, which wake when a player of the run
  comes within their distance, once a run. Experience comes from monsters
  that fought, and from finishing.

## The house style (what the owner wants)

- **Discovery over explanation.** One sign: the title at the gate, with the
  one-line theme and the ranks. Nothing inside explains how to solve
  anything. The adventure's section in `adventures/README.md` advertises (what
  waits there, new gear, new monsters with levels) and never gives the
  solution.
- No talking monsters, no dialogue, no quests given by characters: the place
  tells the story.
- What makes adventures good (see `docs/adventure-design.md`): a safe start;
  choices, loops and more than one way through; danger graded from the start
  inward; a set piece in each part; one boss worth remembering; a reason to
  finish; something that changes from run to run; a warning before anything
  deadly. No instant-death traps.
- Writing: plain British English. Never use em-dashes, in code comments,
  docs, commit messages or replies.

## The builder script

A builder returns a table `g` (see `seed.lua` for a complete one):

```lua
local g = {}
g.info = {
	name = "The Name", line = "The one-line theme, shown at the gate.",
	limit = 60,                     -- minutes
	rank_min = 5, rank_max = 10,
	size = {x = SX, y = SY, z = SZ},
	ground = NG,                    -- the land's ground level in the template
	dig = {{min = ..., max = ...}}, -- what placing clears below the ground
	corner1 = {...}, corner2 = {...},   -- the adventure's box (relative)
	start = {...}, arrival = {...},     -- inside start; outside arrival
	-- optional: kit = {item, ...}, finish_xp, catch_falls, whole_land, ...
}
g.compact = true                    -- save as .ovt (big adventures)
g.spawners, g.chests, g.signs = {}, {}, {}   -- filled by the helpers
g.finish = {...}; g.gate = {...}; g.outside = {...}; g.surface = NF
g.open_for_checks = {...}           -- blocks removed for the walk checks
g.gated = {{label = ..., target = {...}, blocked = {{min, max}}}}
function g.build(origin) ... end     -- writes the blocks with a VoxelManip
function g.plan() ... end            -- a text map, for plan.txt
function g.check_more(O, t) ... end  -- optional extra checks
return g
```

Coordinates are relative to the template's south-west bottom corner: x east,
z north, y up. Players stand at `ground + 1`. Build into a grid and write it
in one go (see `g.build` in `seed.lua`), then set metadata (spawners, chests,
signs).

Helpers every builder has (copy them from `seed.lua` or `wyrm_below.lua`):
`set`, `box`, `air`, `room`, `tunnel`, `sign` (hangs on a wall: `"+x"`, `"-x"`,
`"+z"`, `"-z"`), `spawner(x, y, z, kind, count, wake, {aloft, stealth})`,
`chest(x, y, z, kind)` with kind `common`, `weapon`, `armour` or `finish`.

The gate is `orthoverse_adventure:gate`, outside the box; the board
`orthoverse_adventure:board` beside it. Finishes: `orthoverse_adventure:finish`,
or one in the place's look (`orthoverse_scifi:black_box`,
`orthoverse_props:ledger`, `orthoverse_props:reliquary`). Put the finish
chest beside the finish.

Monsters (`orthoverse_monsters`, kind = the name after the colon) with their
levels: kobold 1, mossling 1, goblin 2, skeleton 3, wisp 3, orc 4, hexer 4,
warlord 5, drone 3, secbot 5, turret 5, warden 7, masked (kobolds in masks),
ringmaster 5, zombie 4, ghoul 5, wight 8, cutthroat 6, deep_orc 8, wyrm 12,
husk 5, crawler 4, spitter 5, spore_puff 4, tendril 6, ganglion 6, nodule 8.
Check `mods/orthoverse_monsters/init.lua` for the current list.

## New blocks, items and monsters

Put an adventure's own blocks in a mod of their own (as `orthoverse_scifi`,
`orthoverse_props`, `orthoverse_seed`), all in the Creative tab so other
builders can use them too, and its monsters in `orthoverse_monsters` with the
`monster()` helper there. Paint textures and synthesise sounds with a Python
script in `tools/<name>/` (Pillow, numpy, ffmpeg; use a venv, never install
packages globally), licensed CC BY-SA 3.0; record the licence of anything
taken from elsewhere.

Rules for that code:
- Anything that changes the world on a player's behalf checks they may: in an
  adventure, a member of its run (or its builder while no run is on);
  elsewhere, `core.is_protected`. Treat everything a player sends (form
  fields, positions, chat) as hostile: check it, never run it.
- Per-run state goes on the run, or in a node's metadata keyed by the run;
  the restore puts the blocks back, not your Lua tables.
- Node timers: blocks in group `orthoverse_timer` have their timer started
  when the adventure is placed and restored, at 1 s; a block that wants
  another interval starts its own timer again in `on_timer`.
- Directions: `/adventure place <name> north` turns the template half round
  (facedir blocks are turned too). Never store coordinates in metadata; find
  things by searching near, and take directions from facedir or from the
  player.

## Generating and checking

Run the builder on a local server (see `tools/adventures/README.md` for the
exact commands; `orthoverse_generate_adventure = <name>` picks the builder).
It writes `<name>.ovt` or `.we`, `<name>.json`, `plan.txt` and `result.txt`.
The checks walk every place a player can stand. Expected:
- `unreachable: none` (every spawner not aloft, every chest, the finish);
- every gated place `false` (unreachable with its ways in walled off);
- the gate reachable from outside, not from inside;
- nobody climbs out; every sign on a wall; `missing nodes: none`.

Then copy the outputs into `adventures/` (the json through
`python3 -m json.tool --tab --sort-keys`).

What the walk checks do not see (learned the hard way):
- **Falls.** The walk drops at most three blocks. A long fall can skip a
  gate: one level's pit opening into another's chamber below, or a drop
  through a blocked space. Add a falling check in `g.check_more` (see
  `reach_falling` in `seed.lua`) and keep levels clear of each other.
- **Things that move or change in a run** (doors, cranes, valves chosen at
  random): check every choice in `g.check_more`.
- **Getting back.** Checks start at the start; a one-way drop is fine only if
  it is meant.
- Low bits of a simple random generator repeat: take the high bits.

## Testing in a game

Place it in a test world on a land, as the admin would (`/adventure place`,
`/adventure save`, `/adventure open`), enter a run, and play through: with a
client under a virtual display, a world mod that moves the player and calls
things, and screenshots (`import -window root`). Positions of blocks are
whole numbers: a player teleported to x.5 stands on a boundary between two.
Look at the screenshots: dark corridors, monsters half in the floor and the
red "no tex" placeholder are found only by looking (a monster drawn as a
cube needs six textures).

## Delivering

The owner applies patches and pushes them himself: never push. Before each
patch, start from GitHub's `main`. One commit per patch, a message that says
what changed and why, then
`git format-patch --binary --start-number <next number> -1` (binary for
images, sounds and .ovt). Split a big adventure into patches that each make
sense: its blocks and gear, its monsters, the adventure itself. Say what you
tested and what you could not, and what needs rebuilding (mods and
templates: `docker compose up -d --build luanti`; templates alone are mounted
and need nothing). Update `docs/adventures.md` (blocks, for builders) and
`adventures/README.md` (placing, and advertising without the solution).
