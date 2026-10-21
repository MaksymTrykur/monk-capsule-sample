#!/bin/sh
# Debug copy: the deploy and preview-url scripts from this checkout replace the image's.
cp /github/workspace/.github/actions/deploy-debug/dynenv-deploy.sh /github/workspace/.github/actions/deploy-debug/preview-url.sh /opt/monk-actions/scripts/
chmod +x /opt/monk-actions/scripts/dynenv-deploy.sh /opt/monk-actions/scripts/preview-url.sh
exec /opt/monk-actions/entrypoints/deploy.sh
