#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Klik"
BUNDLE_ID="com.marino.klik"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

CONFIG="${1:-release}"

echo "→ Building Swift package (${CONFIG})…"
cd "${ROOT}"
swift build -c "${CONFIG}" --arch arm64

BIN_PATH=".build/arm64-apple-macosx/${CONFIG}/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    BIN_PATH=".build/${CONFIG}/${APP_NAME}"
fi
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "❌ Binary not found"
    find .build -name "${APP_NAME}" -type f
    exit 1
fi

echo "→ Assembling app bundle at ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${CONTENTS}/Info.plist"
if [[ -f "${ROOT}/Resources/Klik.icns" ]]; then
    cp "${ROOT}/Resources/Klik.icns" "${RES_DIR}/Klik.icns"
fi

SIGN_IDENTITY="${KLIK_SIGN_IDENTITY:-Apple Development: Marino Glazar (63XD6KB5ZN)}"
echo "→ Signing with: ${SIGN_IDENTITY}"
if ! codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}" 2>&1; then
    echo "⚠️  Stable signing failed — falling back to ad-hoc (TCC permissions will not persist across rebuilds)"
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "✅ Built: ${APP_BUNDLE}"
echo ""
echo "Pokreni s:"
echo "  open \"${APP_BUNDLE}\""
