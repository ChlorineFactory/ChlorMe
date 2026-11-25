#!/usr/bin/env bash
set -euo pipefail

LLAMA_TAG="${1:-b12398}"
mkdir -p Vendor/tmp_llama

PINNED_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"
echo "Trying pinned xcframework URL: ${PINNED_URL}"

if ! curl -fL --retry 3 "${PINNED_URL}" -o Vendor/llama-xcframework.zip; then
  echo "Pinned tag not available, resolving latest xcframework from ggml-org/llama.cpp..."
  AUTH_ARGS=()
  if [ -n "${GH_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${GH_TOKEN}")
  fi
  LATEST_URL=$(curl -sS "${AUTH_ARGS[@]}" "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10" | python3 -c "import json,sys; rels=json.load(sys.stdin); urls=[a['browser_download_url'] for r in rels for a in r.get('assets',[]) if 'xcframework.zip' in a.get('name','')]; print(urls[0] if urls else '')")
  if [ -z "${LATEST_URL}" ]; then
    echo "ERROR: Could not find any xcframework.zip release asset"
    exit 1
  fi
  echo "Resolved latest URL: ${LATEST_URL}"
  curl -fL --retry 3 "${LATEST_URL}" -o Vendor/llama-xcframework.zip
fi

unzip -q Vendor/llama-xcframework.zip -d Vendor/tmp_llama
FOUND_XC=$(find Vendor/tmp_llama -maxdepth 4 -name "llama.xcframework" -type d | head -n 1)
if [ -z "${FOUND_XC}" ]; then
  echo "ERROR: llama.xcframework not found in downloaded zip"
  find Vendor/tmp_llama -maxdepth 4
  exit 1
fi

rm -rf Vendor/llama.xcframework
mv "${FOUND_XC}" Vendor/llama.xcframework
rm -rf Vendor/tmp_llama Vendor/llama-xcframework.zip

# Auto-detect whether llama.xcframework is dynamic or static and adjust XcodeGen embed flag
IOS_BIN=$(find Vendor/llama.xcframework -path "*ios-arm64/*" -name "llama" -type f | head -n 1 || true)
echo "Detected iOS llama binary: ${IOS_BIN}"
if [ -n "${IOS_BIN}" ]; then
  file "${IOS_BIN}" || true
  if file "${IOS_BIN}" | grep -qi "dynamically linked shared library"; then
    echo "Dynamic framework detected -> setting embed: true"
    sed -i '' 's/embed: false/embed: true/' project.yml
  else
    echo "Static framework detected -> keeping embed: false"
  fi
fi
