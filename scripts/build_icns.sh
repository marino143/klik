#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/build/icon-work"
ICONSET="${WORK}/Klik.iconset"
MASTER="${WORK}/icon-1024.png"
OUT_ICNS="${ROOT}/Resources/Klik.icns"

rm -rf "${WORK}"
mkdir -p "${ICONSET}"

echo "→ Generating master 1024×1024 PNG…"
swift "${ROOT}/scripts/generate_icon.swift" "${MASTER}"

echo "→ Generating iconset sizes via sips…"
sips -z 16 16     "${MASTER}" --out "${ICONSET}/icon_16x16.png"          > /dev/null
sips -z 32 32     "${MASTER}" --out "${ICONSET}/icon_16x16@2x.png"       > /dev/null
sips -z 32 32     "${MASTER}" --out "${ICONSET}/icon_32x32.png"          > /dev/null
sips -z 64 64     "${MASTER}" --out "${ICONSET}/icon_32x32@2x.png"       > /dev/null
sips -z 128 128   "${MASTER}" --out "${ICONSET}/icon_128x128.png"        > /dev/null
sips -z 256 256   "${MASTER}" --out "${ICONSET}/icon_128x128@2x.png"     > /dev/null
sips -z 256 256   "${MASTER}" --out "${ICONSET}/icon_256x256.png"        > /dev/null
sips -z 512 512   "${MASTER}" --out "${ICONSET}/icon_256x256@2x.png"     > /dev/null
sips -z 512 512   "${MASTER}" --out "${ICONSET}/icon_512x512.png"        > /dev/null
cp "${MASTER}" "${ICONSET}/icon_512x512@2x.png"

echo "→ Converting iconset → .icns…"
iconutil --convert icns "${ICONSET}" --output "${OUT_ICNS}"

echo "✅ Wrote: ${OUT_ICNS}"
ls -la "${OUT_ICNS}"
