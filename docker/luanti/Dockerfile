# The Orthoverse game server: Luanti (server only) with a static LuaJIT, and
# the Orthoverse game. Build context: the repository root.

# ---------------------------------------------------------------------------
# The crests, one small PNG each, for the land display (orthoverse_landhud)
FROM python:3.12.16-slim-bookworm AS crests
RUN pip install --no-cache-dir pillow==13.0.0
COPY tools/split_crests.py /tmp/
COPY web/heraldry /tmp/heraldry
RUN python /tmp/split_crests.py /tmp/heraldry /tmp/crests

# ---------------------------------------------------------------------------
FROM ubuntu:22.04 AS build

# Ubuntu 22.04's packaged LuaJIT (2017) is too old for Luanti 5.18, so LuaJIT
# is built from its v2.1 branch at a pinned commit (tested 3 Nov 2026).
ARG LUANTI_TAG=5.18.0
ARG LUAJIT_COMMIT=ea9eb7e

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates git cmake g++ make \
      libsqlite3-dev zlib1g-dev libzstd-dev libcurl4-openssl-dev libgmp-dev libjsoncpp-dev libssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone -q -b v2.1 https://github.com/LuaJIT/LuaJIT.git luajit \
 && git -C luajit -c advice.detachedHead=false checkout -q "$LUAJIT_COMMIT" \
 && make -s -C luajit -j"$(nproc)" PREFIX=/opt/luajit amalg >/dev/null \
 && make -s -C luajit PREFIX=/opt/luajit install >/dev/null

# One change to the engine: it gives up (and the server stops with "database
# is locked") when a database has been busy for 3 seconds. The nightly backup
# may hold the map for longer than that while it copies it; the game now
# waits up to a minute for it (a moment of lag, once a night).
RUN git clone -q --depth 1 -b "$LUANTI_TAG" https://github.com/luanti-org/luanti.git luanti \
 && grep -q 'BUSY_FATAL_TRESHOLD   = 3000' luanti/src/database/database-sqlite3.cpp \
 && sed -i 's/BUSY_FATAL_TRESHOLD   = 3000/BUSY_FATAL_TRESHOLD   = 60000/' luanti/src/database/database-sqlite3.cpp \
 && cmake -S luanti -B luanti/build -DBUILD_CLIENT=0 -DBUILD_SERVER=1 -DBUILD_UNITTESTS=0 \
      -DRUN_IN_PLACE=0 -DCMAKE_INSTALL_PREFIX=/opt/luanti \
      -DENABLE_LUAJIT=1 -DLUA_INCLUDE_DIR=/opt/luajit/include/luajit-2.1 \
      -DLUA_LIBRARY=/opt/luajit/lib/libluajit-5.1.a \
      -DENABLE_POSTGRESQL=0 -DENABLE_LEVELDB=0 -DENABLE_REDIS=0 -DENABLE_CURL=1 \
      -DCMAKE_BUILD_TYPE=Release >/dev/null \
 && make -C luanti/build -j"$(nproc)" >/dev/null \
 && make -C luanti/build install >/dev/null

# ---------------------------------------------------------------------------
FROM ubuntu:22.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates libsqlite3-0 sqlite3 zlib1g libzstd1 libcurl4 libgmp10 libjsoncpp25 numactl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/luanti /opt/luanti
# Fail the build now rather than at start-up if a library is missing
RUN ! ldd /opt/luanti/bin/luantiserver | grep "not found" \
 && /opt/luanti/bin/luantiserver --version | head -1

# The game (not the tools, web or snapshot data, which the server never reads)
ARG GAME=/opt/luanti/share/luanti/games/orthoverse
COPY game.conf minetest.conf ${GAME}/
COPY mods ${GAME}/mods
COPY adventures ${GAME}/adventures
COPY --from=crests /tmp/crests ${GAME}/mods/orthoverse_landhud/crests

# The texture pack (OV_TEXTURES in .env: a folder of texturepacks/, or none).
# Textures in the game's own textures/ folder take the place of the mods' ones
# of the same name, for every player, so the pack is copied there.
ARG OV_TEXTURES=soothing32
COPY texturepacks /tmp/texturepacks
RUN if [ "$OV_TEXTURES" != "none" ]; then \
      [ -d "/tmp/texturepacks/$OV_TEXTURES" ] || { echo "No texture pack texturepacks/$OV_TEXTURES" >&2; exit 1; }; \
      mkdir -p ${GAME}/textures \
      && cp -r "/tmp/texturepacks/$OV_TEXTURES/." ${GAME}/textures/ \
      && find ${GAME}/textures -type f ! -name '*.png' -delete; \
    fi \
 && rm -rf /tmp/texturepacks

COPY docker/luanti/entrypoint.sh /usr/local/bin/orthoverse-server
# The server runs as the world's owner (compose sets the user); HOME only
# needs to be somewhere writable.
ENV HOME=/tmp
EXPOSE 30000/udp
ENTRYPOINT ["/usr/local/bin/orthoverse-server"]
CMD ["serve"]
