#!/bin/bash -eu
# Hook called by luanti-wasm's build_www.sh with the new release id.
# Replaces the generic launcher page with the Orthoverse play page.
RELEASE_UUID="$1"
sed "s/%__RELEASE_UUID__%/$RELEASE_UUID/g" orthoverse-play.html > www/index.html
echo "$RELEASE_UUID" > www/RELEASE
echo "Orthoverse play page installed for release $RELEASE_UUID"
