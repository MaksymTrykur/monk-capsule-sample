#!/bin/sh
# Test only: run an unreleased monk-actions from this repo instead of monk-io/monk-actions@v1.
#
# deploy and cleanup are Docker actions whose scripts live in the published image, so the copies here
# build a one-layer image on top of it with the working copy's scripts. build-images is composite
# and runs the scripts next to it. The other actions stay on @v1.
#
# Usage: scripts/sync-actions.sh [path to a monk-actions checkout, default ../monk-actions]
set -eu

SRC=${1:-../monk-actions}
DEST=.github/actions

[ -f "$SRC/deploy/action.yml" ] || { echo "no monk-actions checkout at $SRC" >&2; exit 1; }

rm -rf "$DEST/deploy" "$DEST/cleanup" "$DEST/build-images" "$DEST/scripts"
mkdir -p "$DEST/build-images" "$DEST/scripts"

cp "$SRC"/scripts/* "$DEST/scripts/"

# build-images runs ${{ github.action_path }}/../scripts/...
cp "$SRC/build-images/action.yml" "$DEST/build-images/action.yml"

# deploy, cleanup: the published image plus the working copy's scripts and entrypoints.
for action in deploy cleanup; do
    mkdir -p "$DEST/$action/scripts" "$DEST/$action/entrypoints"
    cp "$SRC"/scripts/* "$DEST/$action/scripts/"
    cp "$SRC"/entrypoints/* "$DEST/$action/entrypoints/"
    cat > "$DEST/$action/Dockerfile" <<'EOF'
FROM images.monk.io/monk-actions:v1
COPY scripts/ /opt/monk-actions/scripts/
COPY entrypoints/ /opt/monk-actions/entrypoints/
RUN chmod +x /opt/monk-actions/scripts/*.sh /opt/monk-actions/entrypoints/*.sh
EOF
    sed 's|image: docker://.*|image: Dockerfile|' "$SRC/$action/action.yml" > "$DEST/$action/action.yml"
    grep -q '^  image: Dockerfile' "$DEST/$action/action.yml" || { echo "$action/action.yml has no image line to override" >&2; exit 1; }
done

echo "synced from $SRC"
