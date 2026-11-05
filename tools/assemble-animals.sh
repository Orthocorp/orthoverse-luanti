#!/usr/bin/env bash
# Pull Animalia (animals) and Creatura (the mob library it runs on) into
# mods/animals (a modpack) so the game is self-contained.
# Usage: tools/assemble-animals.sh   (the commits tested below)
set -euo pipefail
ANIMALIA_REF="${ANIMALIA_REF:-5895f40}"   # 4 Mar 2026
CREATURA_REF="${CREATURA_REF:-4eb507c}"   # 25 Dec 2025
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
git clone -q https://github.com/ElCeejo/animalia.git "$tmp/animalia"
git -C "$tmp/animalia" -c advice.detachedHead=false checkout -q "$ANIMALIA_REF"
git clone -q https://github.com/ElCeejo/creatura.git "$tmp/creatura"
git -C "$tmp/creatura" -c advice.detachedHead=false checkout -q "$CREATURA_REF"
rm -rf mods/animals
mkdir -p mods/animals
for m in animalia creatura; do
	rm -rf "$tmp/$m/.git" "$tmp/$m/.github"
	cp -r "$tmp/$m" mods/animals/
done
# Some files come with Windows line endings, which git am would convert when
# this is passed on as a patch; use plain line endings (Luanti reads either)
find mods/animals -type f \( -name '*.lua' -o -name '*.conf' -o -name '*.txt' -o -name '*.md' -o -name 'LICENSE' \) \
	-exec sed -i 's/\r$//' {} +
printf 'name = animals\ndescription = Animalia %s and Creatura %s (vendored, MIT)\n' \
	"$ANIMALIA_REF" "$CREATURA_REF" > mods/animals/modpack.conf
rm -rf "$tmp"
echo "Animalia $ANIMALIA_REF and Creatura $CREATURA_REF copied into mods/animals"
