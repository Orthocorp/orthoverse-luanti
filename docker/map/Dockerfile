# Draws the web map (tiles and the land list) from the world, read-only.
# Build context: the repository root.
FROM python:3.12.7-slim-bookworm AS base
RUN pip install --no-cache-dir numpy==2.1.3 zstandard==0.23.0 pillow==11.0.0

# The average colour of every texture in the game's mods, so that what players
# build with shows in its own colour (only the result goes into the image)
FROM base AS colours
COPY tools/texture_colours.py /tmp/
COPY mods /tmp/mods
RUN python /tmp/texture_colours.py /tmp/mods > /tmp/texture_colours.json

FROM base
WORKDIR /app
COPY tools/render_map.py tools/
COPY --from=colours /tmp/texture_colours.json tools/texture_colours.json
COPY web/map/make_tiles.py web/map/cards.py web/map/
COPY web/map/fonts web/map/fonts
COPY web/heraldry /app/heraldry
COPY mods/orthoverse_lands/data/lands.json data/lands.json
COPY docker/map/make-map.sh /usr/local/bin/make-map

ENTRYPOINT ["/usr/local/bin/make-map"]
