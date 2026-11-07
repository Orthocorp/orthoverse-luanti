# Builds the browser game (paradust7/luanti-wasm, pinned) with the Orthoverse
# engine patches and play page. Build context: the repository root.
#
# The layers follow how often things change, so Docker redoes only what is
# needed: the Emscripten SDK and the support libraries (rarely: only when the
# pin moves), then the engine with web/client/patches (when a patch changes;
# a build cache keeps it incremental), and the play page last (seconds).
#
#   docker compose run --rm --build client

FROM ubuntu:22.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates wget git python3 build-essential cmake tclsh zip zstd gettext xz-utils rsync \
 && rm -rf /var/lib/apt/lists/*

# luanti-wasm needs Node 24 to build
COPY --from=node:24.22.0-bookworm-slim /usr/local/bin/node /usr/local/bin/node

ARG LUANTI_WASM_COMMIT=5bfae52b53605b39667dfc29cddd59c861e38111
RUN git clone -q https://github.com/paradust7/luanti-wasm.git /luanti-wasm \
 && git -C /luanti-wasm -c advice.detachedHead=false checkout -q "$LUANTI_WASM_COMMIT"
WORKDIR /luanti-wasm

# Emscripten 6 builds real shared libraries. zstd and libzip build a .so next
# to their .a, the linker then prefers libzstd.so, and the test programs that
# libarchive's configure runs fail to load it ("cannot compute sizeof
# (wchar_t)"). Build those two as static libraries only.
RUN for f in build_zstd.sh build_libzip.sh; do \
      sed -i '/^emcmake cmake \\$/a\  -DBUILD_SHARED_LIBS=OFF -DZSTD_BUILD_SHARED=OFF \\' "$f"; \
      grep -q -- '-DBUILD_SHARED_LIBS=OFF' "$f" || exit 1; \
    done

# The Emscripten SDK (about 3 GB)
RUN ./install_emsdk.sh > /tmp/emsdk.log 2>&1 || { tail -n 40 /tmp/emsdk.log; exit 1; }

# The support libraries: what build_all.sh does before the engine
RUN { bash -c 'source ./common.sh && emcc --clear-cache --clear-ports' \
      && ./fetch_sources.sh \
      && ./build_zstd.sh && ./build_libarchive.sh && ./build_webshims.sh \
      && ./build_openssl.sh && ./build_curl.sh && ./build_libzip.sh ; } > /tmp/libs.log 2>&1 \
    || { tail -n 40 /tmp/libs.log; exit 1; }

# The engine with the Orthoverse patches, then its file system pack and the
# release files in www/ (see build-engine.sh; the build cache keeps engine
# rebuilds incremental)
COPY web/client/patches/ /patches/
COPY web/client/textures/ /textures/
COPY docker/client/build-engine.sh /usr/local/bin/build-engine
RUN --mount=type=cache,target=/cache,id=orthoverse-luanti-wasm-engine \
    build-engine "$LUANTI_WASM_COMMIT" > /tmp/engine.log 2>&1 \
    || { tail -n 40 /tmp/engine.log; exit 1; }

# The play page, applied when installing (see install.sh)
COPY web/client/play.html /luanti-wasm/orthoverse-play.html
COPY docker/client/install.sh /usr/local/bin/install-client

CMD ["/usr/local/bin/install-client"]
