#!/usr/bin/env python3
"""Download the sources of Emscripten's ports before Emscripten wants them.

Emscripten fetches a port's source the first time something is compiled with
it, with one try and no other address. A busy GitHub (a 503 from its release
downloads, say) then fails the whole build. This fetches each port the engine
needs, with retries and, where one exists, a second address, checks it against
the hash Emscripten expects, and unpacks it where Emscripten looks, with the
marker that tells Emscripten it is already there.

Run from /luanti-wasm, after the Emscripten SDK is installed.
"""
import hashlib
import os
import shutil
import sys
import tempfile
import time
import types
import urllib.request

EMSCRIPTEN = "emsdk/upstream/emscripten"
PORTS_DIR = os.path.join(EMSCRIPTEN, "cache", "ports")
NEEDED = ["sdl2", "zlib", "libjpeg", "libpng", "freetype", "ogg", "vorbis", "sqlite3"]

# Other places with the very same files (the hash is checked whichever is used)
MIRRORS = {
    "ogg": ["https://downloads.xiph.org/releases/ogg/{file}",
            "https://ftp.osuosl.org/pub/xiph/releases/ogg/{file}"],
    "vorbis": ["https://downloads.xiph.org/releases/vorbis/{file}",
               "https://ftp.osuosl.org/pub/xiph/releases/vorbis/{file}"],
}
WAITS = [0, 15, 30, 60, 90, 120]   # seconds before each round of tries


class Found(Exception):
    pass


def port_source(name):
    """The (url, sha512) a port fetches, read by running its get() up to the fetch."""
    path = os.path.join(EMSCRIPTEN, "tools", "ports", name + ".py")
    module = types.ModuleType(name)
    module.__file__ = path
    with open(path) as f:
        exec(compile(f.read(), path, "exec"), module.__dict__)

    def fetch_project(_name, url, sha512hash=None):
        raise Found(url, sha512hash)

    ports = types.SimpleNamespace(fetch_project=fetch_project)
    settings = types.SimpleNamespace(PTHREADS=1, USE_SDL=2, SUPPORT_LONGJMP="wasm")
    try:
        module.get(ports, settings, types.SimpleNamespace())
    except Found as found:
        return found.args
    sys.exit(f"fetch-ports: could not tell where port {name} comes from")


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "orthoverse-client-build"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def fetch(name):
    url, sha512 = port_source(name)
    target = os.path.join(PORTS_DIR, name)
    marker = os.path.join(target, ".emscripten_url")
    if os.path.exists(marker) and open(marker).read().strip() == url:
        print(f"fetch-ports: {name} already here")
        return
    file = url.rsplit("/", 1)[-1]
    addresses = [url] + [m.format(file=file) for m in MIRRORS.get(name, [])]
    for wait in WAITS:
        time.sleep(wait)
        for address in addresses:
            try:
                data = download(address)
            except Exception as e:
                print(f"fetch-ports: {name} from {address}: {e}")
                continue
            if sha512 and hashlib.sha512(data).hexdigest() != sha512:
                print(f"fetch-ports: {name} from {address}: not the expected file (hash differs)")
                continue
            os.makedirs(PORTS_DIR, exist_ok=True)
            ext = file.split(".", 1)[1]
            with tempfile.TemporaryDirectory(dir=PORTS_DIR) as tmp:
                archive = os.path.join(tmp, "source." + ext)
                with open(archive, "wb") as f:
                    f.write(data)
                unpacked = os.path.join(tmp, "unpacked")
                shutil.unpack_archive(archive, unpacked)
                with open(os.path.join(unpacked, ".emscripten_url"), "w") as f:
                    f.write(url + "\n")
                shutil.rmtree(target, ignore_errors=True)
                os.replace(unpacked, target)
            print(f"fetch-ports: {name} from {address}")
            return
    sys.exit(f"fetch-ports: could not download port {name} (tried {', '.join(addresses)})")


if __name__ == "__main__":
    for port in NEEDED:
        fetch(port)
