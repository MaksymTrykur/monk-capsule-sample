#!/bin/sh
# Test only: run an unreleased monk-actions checkout instead of monk-io/monk-actions@v1.
#
# The Docker actions (provision, fetch-metadata, deploy, cleanup) keep their scripts in the published
# image, so each copy here builds a one-layer image on top of it with the checkout's scripts.
# build-images is composite and runs the scripts next to it.
#
# Usage: scripts/use-local-actions.sh <path to a monk-actions checkout>
set -eu

SRC=${1:?"usage: $0 <monk-actions checkout>"}
DEST=.github/actions
[ -f "$SRC/deploy/action.yml" ] || { echo "no monk-actions checkout at $SRC" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/scripts" "$DEST/build-images"
cp "$SRC"/scripts/* "$DEST/scripts/"
cp "$SRC/build-images/action.yml" "$DEST/build-images/action.yml"

for a in provision fetch-metadata deploy cleanup; do
    mkdir -p "$DEST/$a/scripts" "$DEST/$a/entrypoints"
    cp "$SRC"/scripts/* "$DEST/$a/scripts/"
    cp "$SRC"/entrypoints/* "$DEST/$a/entrypoints/"
    cat > "$DEST/$a/Dockerfile" <<'EOF'
FROM images.monk.io/monk-actions:v1
COPY scripts/ /opt/monk-actions/scripts/
COPY entrypoints/ /opt/monk-actions/entrypoints/
RUN chmod +x /opt/monk-actions/scripts/*.sh /opt/monk-actions/entrypoints/*.sh
EOF
    sed 's|image: docker://.*|image: Dockerfile|' "$SRC/$a/action.yml" > "$DEST/$a/action.yml"
    grep -q '^  image: Dockerfile' "$DEST/$a/action.yml" || { echo "$a/action.yml has no image line to override" >&2; exit 1; }
done

# The workflow runs the local copies; fetch-metadata needs a checkout first to have them.
python3 - <<'PY'
import re
f = '.github/workflows/dynenv.yml'
s = open(f).read()
s = re.sub(r'monk-io/monk-actions/(provision|fetch-metadata|deploy|cleanup|build-images)@v1', r'./.github/actions/\1', s)
old = "    steps:\n      - id: meta\n        uses: ./.github/actions/fetch-metadata"
if old in s:
    s = s.replace(old, "    steps:\n      - uses: actions/checkout@v4\n      - id: meta\n        uses: ./.github/actions/fetch-metadata", 1)
open(f, 'w').write(s)
PY
echo "now running the actions from $SRC"
