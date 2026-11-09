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

## The Gullet

`gullet.lua` builds The Gullet the same way, and `generate_gullet/` is its world mod: it builds it in the sky, saves `gullet.we` and `gullet.json`, and checks with a walk through every place a player can stand that the start leads to every spawner, chest and the finish, and that the temple cannot be reached without the orc hall's passage or the secret way. It leaves the server running, so a test can then place and play it.

```
mkdir -p /tmp/gu/world/worldmods
cp -r tools/adventures/generate_gullet /tmp/gu/world/worldmods/
printf 'gameid = orthoverse\nbackend = sqlite3\n' > /tmp/gu/world/world.mt
printf 'max_forceloaded_blocks = 300\nbind_address = 127.0.0.1\nipv6_server = false\nport = 30777\n' > /tmp/gu/test.conf
luantiserver --config /tmp/gu/test.conf --world /tmp/gu/world --gameid orthoverse   # stop it after "temple reachable ..."
cat /tmp/gu/world/result.txt
cp /tmp/gu/world/gullet.we adventures/
python3 -m json.tool --tab --sort-keys /tmp/gu/world/gullet.json > adventures/gullet.json
```

Expected: `finish reachable true; unreachable: none`, `temple reachable without the two ways in: false`, `gate reachable from outside: true`, `the rim can be climbed from the land: false`, `fort reachable from inside: false`, `can climb out of the gorge: false` and `signs not on a wall: none`.
