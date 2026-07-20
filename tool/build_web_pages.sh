#!/usr/bin/env bash
# Build the web light client for Cloudflare Pages and stage it at
# website/app/ (deployed at https://aura-omnimesh.pages.dev/app/).
#
# Pages caps static files at 25 MB, so the 76 MB model cannot live in the
# bundle. The app fetches it at runtime from MODEL_URL instead. The default
# is the SAME-ORIGIN proxy served by functions/model/[file].js — GitHub
# release assets send no CORS headers, so a cross-origin fetch from the
# browser would be blocked; the proxy sidesteps CORS entirely.
#
# Usage:
#   tool/build_web_pages.sh [MODEL_URL]
#
# After running: commit website/app/** (kept as plain git blobs by
# .gitattributes — Pages git builds do not smudge LFS pointers) and push,
# or deploy directly:
#   wrangler pages deploy website --project-name aura-omnimesh
set -euo pipefail

MODEL_URL="${1:-/model/minilm_multilingual_trimmed_v2.onnx}"
MODEL_ASSET="build/web/assets/assets/models/minilm_multilingual_trimmed_v2.onnx"

echo "Building web with AURA_WEB_MODEL_URL=$MODEL_URL"
# MSYS_NO_PATHCONV: Git Bash on Windows otherwise rewrites /app/ and the
# leading-slash MODEL_URL into C:/Program Files/Git/... paths.
MSYS_NO_PATHCONV=1 flutter build web --release \
  --base-href /app/ \
  --dart-define="AURA_WEB_MODEL_URL=$MODEL_URL"

# Strip the bundled model so the deploy fits the 25 MB/file cap; the web
# ONNX path uses the URL, never the bundle, when AURA_WEB_MODEL_URL is set.
if [ -f "$MODEL_ASSET" ]; then
  size=$(wc -c < "$MODEL_ASSET")
  rm -f "$MODEL_ASSET"
  echo "Stripped bundled model ($size bytes); web fetches it from the URL."
fi
# Guard against stale local test artifacts (web/model/) leaking into the
# deploy — anything >25 MB fails Pages validation.
rm -rf build/web/model

echo "Staging build/web -> website/app"
rm -rf website/app
cp -r build/web website/app

over=$(find website -type f -size +25M | wc -l)
if [ "$over" -ne 0 ]; then
  echo "ERROR: files over the Pages 25 MB cap:" >&2
  find website -type f -size +25M >&2
  exit 1
fi
echo "Done. Commit website/app/** + push, or: wrangler pages deploy website"
