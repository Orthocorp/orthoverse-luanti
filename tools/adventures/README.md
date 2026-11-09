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

## The Gullet, The Fallen Star and The Mill

`gullet.lua`, `fallen_star.lua` and `mill.lua` build them the same way, and `generate_adventure/` is their world mod: setting `orthoverse_generate_adventure` names which (`gullet`, the default, `fallen_star` or `mill`). It builds it in the sky, writes `<name>.we`, `<name>.json` and `plan.txt` (a map below the ground), opens its card and blast doors (players carry the cards), and checks with a walk through every place a player can stand:
- that the start leads to every spawner (but turrets on ledges), chest, locker and the finish;
- that each gated place (the Gullet's temple; the Fallen Star's reactor, armoury and lower passage; the Mill's river) cannot be reached with its ways in walled off;
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

The ship's textures and sounds, the locker's and the robots' come from `tools/scifi/make_textures.py`; the mill's fittings and its two new monsters' from `tools/props/make_textures.py`. The checks cannot ride a boat: the Mill's river is checked by its culvert, with the sluice open.
