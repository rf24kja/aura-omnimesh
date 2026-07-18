#!/usr/bin/env bash
# Build the web light client for a size-capped static host (Cloudflare
# Pages caps files at 25 MB, so the 76 MB model cannot live in the
# bundle). The model is fetched at runtime from a URL instead; the vocab
# (4.3 MB) and everything else stay bundled.
#
# Usage:
#   tool/build_web_pages.sh [MODEL_URL]
# Default MODEL_URL is the GitHub release asset (create a release that
# carries minilm_multilingual_trimmed_v2.onnx). The URL host must send
# permissive CORS — GitHub release assets do.
#
# Output: build/web — deploy this directory to Pages (build output dir).
set -euo pipefail

MODEL_URL="${1:-https://github.com/rf24kja/aura-omnimesh/releases/latest/download/minilm_multilingual_trimmed_v2.onnx}"
MODEL_ASSET="build/web/assets/assets/models/minilm_multilingual_trimmed_v2.onnx"

echo "Building web with AURA_WEB_MODEL_URL=$MODEL_URL"
flutter build web --release --dart-define="AURA_WEB_MODEL_URL=$MODEL_URL"

# Strip the bundled model so the deploy fits the 25 MB/file cap; the app
# fetches it from MODEL_URL at runtime instead.
if [ -f "$MODEL_ASSET" ]; then
  size=$(wc -c < "$MODEL_ASSET")
  rm -f "$MODEL_ASSET"
  # Keep the AssetManifest honest is unnecessary — the web ONNX path uses
  # the URL, never the bundle, when AURA_WEB_MODEL_URL is set.
  echo "Stripped bundled model ($size bytes); web fetches it from the URL."
fi

echo "Done. Deploy build/web (Pages build output dir = build/web, or copy"
echo "to website/app for a single deploy)."
