#!/usr/bin/env python3
"""Build mods/orthoverse_lands/data/lands.json from the old Orthoverse snapshot.

Sources (from the old repos):
  voxel.json          orthoverse-offline/true-database/voxel.json
                      (identical to orthoverse-prismarine/.../lands/voxel.json,
                      last updated 6 Apr 2023: the data the last live server used)
  special.json        orthoverse-prismarine/patch-files/flying-squid/map-data/special.json
  sqlite dump         orthoverse-offline/orthoverse-sqlite.dump (descriptions only)

Positions in voxel.json are authoritative and frozen. Coordinates use the old
Orthoverse convention: key "x:z" with z increasing southwards (Minecraft style).
The mod converts to Luanti coordinates (z increasing northwards).

Standard library only; run with: python3 tools/build_lands.py VOXEL SPECIAL DUMP OUT
"""
import json
import re
import sqlite3
import sys


def load_descriptions(dump_path):
    """Return {token_id_lower: (description, special)} from the SQLite dump."""
    con = sqlite3.connect(":memory:")
    with open(dump_path, encoding="utf-8") as f:
        con.executescript(f.read())
    out = {}
    for token, desc, special in con.execute(
            "SELECT tokenId, description, special FROM land"):
        out[token.lower()] = (desc, special)
    return out


def clean_feature(s):
    """Henge feature strings: strip an accidental 0x prefix, keep 36 tile chars."""
    s = s.lower()
    if s.startswith("0x"):
        s = s[2:]
    if not re.fullmatch(r"[0-9a-f]{36,40}", s):
        raise ValueError("bad feature string: " + s)
    return s[:36]


def main(voxel_path, special_path, dump_path, out_path):
    with open(voxel_path, encoding="utf-8") as f:
        voxel = json.load(f)
    with open(special_path, encoding="utf-8") as f:
        special = json.load(f)
    descs = load_descriptions(dump_path)

    lands = {}
    for key, (token, name, level, crest, owner) in voxel.items():
        token = token.lower()
        if not re.fullmatch(r"0x[0-9a-f]{40}", token):
            raise ValueError("bad token id at " + key)
        x, z = (int(v) for v in key.split(":"))
        entry = {
            "token": token,
            "name": name,
            "level": int(level),
            "crest": None if crest == "none" else crest,
            "owner_snapshot": owner.lower(),
        }
        d = descs.get(token)
        if d:
            entry["description"] = d[0]
            if d[1] not in ("no", None):
                entry["special"] = d[1]
        lands["%d:%d" % (x, z)] = entry

    henges = {}
    for key, s in special.items():
        if s.get("function") != "henge":
            continue
        henges[key] = {"name": s["name"], "feature": clean_feature(s["feature"])}
        if key not in lands:
            raise ValueError("henge without a land entry: " + key)

    out = {
        "format": 1,
        "comment": "Orthoverse lands, frozen positions. Key 'x:z' in old Orthoverse "
                   "coordinates (z grows southwards). Terrain comes from 'token'; "
                   "'owner_snapshot' is the owner as of Apr 2023, not authoritative.",
        "land_size": 96,
        "map_radius": 56,
        "lands": lands,
        "henges": henges,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print("lands: %d, henges: %d -> %s" % (len(lands), len(henges), out_path))


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
