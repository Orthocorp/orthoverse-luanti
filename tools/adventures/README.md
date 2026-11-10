# Making the ready-made adventures

`three_bells.lua` builds The Three Bells in a world, node by node, from a plan in code. `generate/` is a world mod that runs it on a local server. It does the following:
- builds the adventure in the sky
- lets the Mesecons settle
- saves it as `three-bells.we` and `three-bells.json` in the world folder
- checks every puzzle in that copy
- places a second copy on a land the way `/adventure place` does, and checks every puzzle again
- writes what it found to `result.txt` and stops the server

To regenerate after changing `three_bells.lua`:

```
mkdir -p /tmp/tb/world/worldmods
cp -r tools/adventures/generate /tmp/tb/world/worldmods/
printf 'gameid = orthoverse\nbackend = sqlite3\n' > /tmp/tb/world/world.mt
printf 'max_forceloaded_blocks = 200\nbind_address = 127.0.0.1\nipv6_server = false\nport = 30777\n' > /tmp/tb/test.conf
luantiserver --config /tmp/tb/test.conf --world /tmp/tb/world --gameid orthoverse
cat /tmp/tb/world/result.txt
cp /tmp/tb/world/three-bells.we adventures/
python3 -m json.tool --tab --sort-keys /tmp/tb/world/three-bells.json > adventures/three-bells.json
```

The game must be installed from this repository, so that its path holds `tools/`. The test forceloads the area, because torches and pressure plates only work in active blocks, which otherwise need a player nearby.

Every door should read `closed` at the start. Each puzzle step should then open its door: the grate with a pebble on the plate, the library with the real lever, the levers at high, low, high, low, and the three ropes.

## The Gullet, The Fallen Star, The Mill, St Morwen's and The Wyrm Below

`gullet.lua`, `fallen_star.lua`, `mill.lua`, `st_morwens.lua` and `wyrm_below.lua` build them the same way, and `generate_adventure/` is their world mod: setting `orthoverse_generate_adventure` names which (`gullet`, the default, `fallen_star`, `mill`, `st_morwens` or `wyrm_below`). It builds it in the sky, writes `<name>.we` (or `<name>.ovt`, the compact form, for The Wyrm Below), `<name>.json` and `plan.txt` (a map below the ground), opens its card and blast doors (players carry the cards) and St Morwen's crypt gate and secret floor, raises The Wyrm Below's bridge, and checks with a walk through every place a player can stand (Tir Na Nog, a climb, has its own checks: below):
- that the start leads to every spawner (but turrets on ledges), chest, locker and the finish;
- that each gated place (the Gullet's temple; the Fallen Star's reactor, armoury and lower passage; the Mill's river; St Morwen's tomb; The Wyrm Below's far shore, with the bridge) cannot be reached with its ways in walled off;
- that the gate can be reached from open ground outside, but not from inside;
- that nobody climbs out, or up onto the rim's barrier from the land;
- that every sign hangs on a wall.

```
mkdir -p /tmp/gu/world/worldmods
cp -r tools/adventures/generate_adventure /tmp/gu/world/worldmods/
printf 'gameid = orthoverse\nbackend = sqlite3\n' > /tmp/gu/world/world.mt
printf 'max_forceloaded_blocks = 300\nbind_address = 127.0.0.1\nipv6_server = false\nport = 30777\northoverse_generate_adventure = fallen_star\n' > /tmp/gu/test.conf
luantiserver --config /tmp/gu/test.conf --world /tmp/gu/world --gameid orthoverse   # stop it after "signs not on a wall"
cat /tmp/gu/world/result.txt
cp /tmp/gu/world/fallen_star.we adventures/
python3 -m json.tool --tab --sort-keys /tmp/gu/world/fallen_star.json > adventures/fallen_star.json
```

Expected: `unreachable: none`, `finish reachable true`, every gated place `(with them: true): false`, `gate reachable from outside: true`, `the rim can be climbed from the land: false`, `entrance reachable from inside: false`, `can climb out: false` and `signs not on a wall: none`.

The ship's textures and sounds, the locker's and the robots' come from `tools/scifi/make_textures.py`; the mill's fittings and its two new monsters' from `tools/props/make_textures.py`; St Morwen's fittings, the zombie, the ghoul and the wight, and their sounds, from `tools/props/make_st_morwens.py`. The checks cannot ride a boat: the Mill's river is checked by its culvert, with the sluice open. Nor climb a ladder: St Morwen's tower (its landings and belfry) is left out of the walk.

The Wyrm Below is big (80 x 80 x 80), so give the generating server room to forceload it (`max_forceloaded_blocks = 400`), and copy `wyrm_below.ovt` instead of a `.we`:

```
cp /tmp/gu/world/wyrm_below.ovt adventures/
python3 -m json.tool --tab --sort-keys /tmp/gu/world/wyrm_below.json > adventures/wyrm_below.json
```

The checks treat lava (anything that burns) as no place to stand. The wyrm's ring and bridge are in `mods/orthoverse_props`, the wyrm, the cutthroat and the deep orc in `mods/orthoverse_monsters`.

## Tir Na Nog

`tir_na_nog.lua` builds it the same way, with `orthoverse_generate_adventure = tir_na_nog` and room to forceload it (`max_forceloaded_blocks = 400`). It is a climb, not a walk, so it has its own checks (`g.check`): from the start, with jumps (one up within 3.2 blocks between the stones' middles, level within 4.1, down within 4.6) and the ladder, every checkpoint, the finish and the chest can be reached, through three mazes made the way a run makes them; and where a part is first out of reach, if it is. The ghost steps are all made solid for the checks. Expected: `unreachable: none` and `finish reachable true` for each maze, and `deepest stone below its checkpoint: 0` (the wind catches 6 below).

```
cp /tmp/gu/world/tir_na_nog.ovt adventures/
python3 -m json.tool --tab --sort-keys /tmp/gu/world/tir_na_nog.json > adventures/tir_na_nog.json
```

Its `.json` uses what a sky adventure needs from `/adventure place`:
- `whole_land`: placed over the whole land, from its south-west corner, its `ground` (here negative: the box's floor is above the ground) taken from the map's ground level, wherever the admin stands;
- `keep_ground`: nothing is cleared or dug but the `clear` boxes, and only the template's own blocks are set (not its air), so the land stays as it is;
- `nodes`: blocks outside the box, set one by one (the gate and its pad on the mountain top);
- `footprint`: what is protected besides the box (the gate's pad);
- `approach`, `approach_line`: where going there from the Adventures page puts a player, and what they are told, when the gate is hard to get to;
- `catch_falls`: checkpoints (`orthoverse_adventure:checkpoint`), the wind that catches a fall, and no fall damage, in a run;
- `maze`: the corners of a maze made anew at the start of each run (`orthoverse.adventure.make_maze`);
- `finish_xp`: the finishing bonus (300; otherwise 200), once a day.

The ghost steps are `orthoverse_props:ghost_step` (param2 0 to 7 sets when each comes and goes).
