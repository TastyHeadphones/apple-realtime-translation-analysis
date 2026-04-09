#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/ios26_demo/Vendor/llama.swift/Artifacts"
XCFRAMEWORK_DIR="$ARTIFACT_DIR/llama-cpp.xcframework"
DOWNLOAD_URL="https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip"

if [[ -d "$XCFRAMEWORK_DIR" ]]; then
  echo "llama runtime already present at: $XCFRAMEWORK_DIR"
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/llama-cpp.xcframework.zip"

echo "Downloading llama runtime..."
curl -L --fail --retry 3 --output "$archive" "$DOWNLOAD_URL"

echo "Extracting runtime..."
unzip -q "$archive" -d "$tmpdir/extracted"

found_xcframework="$(find "$tmpdir/extracted" -type d -name "llama-cpp.xcframework" | head -n 1)"
if [[ -z "${found_xcframework:-}" ]]; then
  echo "Failed to locate llama-cpp.xcframework in the downloaded archive." >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"
rm -rf "$XCFRAMEWORK_DIR"
cp -R "$found_xcframework" "$ARTIFACT_DIR/"

echo "Installed llama runtime to: $XCFRAMEWORK_DIR"
