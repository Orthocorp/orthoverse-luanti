# Texture packs

A texture pack here changes how the world looks for every player, browser and
desktop alike: the server image copies the pack chosen by `OV_TEXTURES` in
`.env` into the game's own `textures/` folder, whose textures take the place of
the mods' ones of the same name. `OV_TEXTURES=none` keeps Minetest Game's own
textures. After changing it: `docker compose up -d --build luanti`; players see
the change when they next join (the server sends them the new pictures).

| Folder | Pack | Licence |
| --- | --- | --- |
| `soothing32/` | [Soothing 32](https://content.luanti.org/packages/Zughy/soothing32/) by Zughy and contributors: 32 colours, 16 x 16 | CC BY-SA 4.0 (`soothing32/LICENSE`) |

Only the pack's textures for blocks and items this game has are kept (the pack
also covers mods the Orthoverse does not use). It does not cover the Animalia
animals, the farming crops or the Orthoverse's own textures, which keep their
look.

The web map and the token cards keep their colours either way.
