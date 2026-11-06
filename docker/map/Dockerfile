# Draws the web map (tiles and the land list) from the world, read-only.
# Build context: the repository root.
FROM python:3.12.7-slim-bookworm

RUN pip install --no-cache-dir numpy==2.1.3 zstandard==0.23.0 pillow==11.0.0

WORKDIR /app
COPY tools/render_map.py tools/
COPY web/map/make_tiles.py web/map/cards.py web/map/
COPY web/heraldry /app/heraldry
COPY mods/orthoverse_lands/data/lands.json data/lands.json
COPY docker/map/make-map.sh /usr/local/bin/make-map

ENTRYPOINT ["/usr/local/bin/make-map"]
