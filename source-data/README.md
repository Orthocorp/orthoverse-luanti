# Source data

Snapshot files from the old Orthoverse, used by `tools/build_lands.py`.

- `voxel.json`: the land table the last live server used (6 April 2023), keyed by
  land position `"x:z"` (z grows south). Each entry: token ID, name, level, crest
  image, owner at the time. From `orthoverse-offline/true-database/voxel.json`
  (identical to `orthoverse-prismarine/.../lands/voxel.json`).
- `special.json`: the nine henges and their tile feature strings, from
  `orthoverse-prismarine/patch-files/flying-squid/map-data/special.json`.
- `orthoverse-sqlite.dump`: the orthoverse-offline land database (August 2022
  reveals), used here only for land descriptions.

Owner addresses in these files are public chain data as of 2023 and are not used
for permissions.
