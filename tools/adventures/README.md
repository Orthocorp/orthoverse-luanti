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
