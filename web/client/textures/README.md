# Engine textures for the browser game

PNG files here replace the engine's own textures of the same name
(`textures/base/pack/` in Luanti) in the browser game the `client` service
builds. These are textures the engine draws before it has the server's files,
such as the loading bar, so the game itself cannot change them.

| File | What | From | Licence |
| --- | --- | --- | --- |
| `progress_bar.png`, `progress_bar_bg.png` | The loading bar as a sword, the blade filling as the game loads | [Progress Bar Sword](https://content.luanti.org/packages/LoopyAntenna/progressbar_sword/) by LoopyAntenna, 2024 | CC BY-SA 3.0 Unported |

The sword is LoopyAntenna's 64 x 12 pixel art, enlarged 6 times here rather
than the original 8: the engine draws the loading bar no taller than 72 pixels,
so at 96 it would be squashed.
