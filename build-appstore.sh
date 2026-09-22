#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Klik"
BUNDLE_ID="hr.codigit.klik"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${ROOT}/build-appstore"
APP_BUNDLE="${BUILD_ROOT}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"
PROFILE_PATH="${KLIK_APPSTORE_PROFILE:-}"
SIGN_IDENTITY="${KLIK_APPSTORE_SIGN_IDENTITY:-Apple Development: Marino Glazar (63XD6KB5ZN)}"
ENTITLEMENTS_PATH="${ROOT}/Resources/Klik-AppStore.entitlements"

echo "→ Building sandboxed Mac App Store variant…"
cd "${ROOT}"
KLIK_APP_STORE=1 swift build -c release --arch arm64

BIN_PATH=".build/arm64-apple-macosx/release/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    BIN_PATH=".build/release/${APP_NAME}"
fi
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "❌ Binary not found" >&2
    exit 1
fi

echo "→ Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT}/Resources/Info-AppStore.plist" "${CONTENTS}/Info.plist"
cp "${ROOT}/Resources/Klik.icns" "${RES_DIR}/Klik.icns"
cp "${ROOT}/Sources/CWebRTCAEC3/LICENSE.webrtc-aec3" "${RES_DIR}/WebRTC-AEC3-LICENSE.txt"

if [[ -n "${PROFILE_PATH}" ]]; then
    if [[ ! -f "${PROFILE_PATH}" ]]; then
        echo "❌ Provisioning profile not found: ${PROFILE_PATH}" >&2
        exit 1
    fi
    cp "${PROFILE_PATH}" "${CONTENTS}/embedded.provisionprofile"
    ENTITLEMENTS_PATH="${ROOT}/Resources/Klik-AppStore-Distribution.entitlements"
fi

echo "→ Signing with ${SIGN_IDENTITY}…"
codesign --force --timestamp --options runtime \
    --entitlements "${ENTITLEMENTS_PATH}" \
    --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

if otool -L "${MACOS_DIR}/${APP_NAME}" | grep -q Sparkle; then
    echo "❌ Store binary unexpectedly links Sparkle" >&2
    exit 1
fi
if find "${APP_BUNDLE}" -iname '*Sparkle*' -print -quit | grep -q .; then
    echo "❌ Store bundle unexpectedly contains Sparkle" >&2
    exit 1
fi

echo "✅ App Store build: ${APP_BUNDLE}"
echo "   Bundle ID: ${BUNDLE_ID}"
echo "   Sparkle: absent"
echo "   Sandbox: enabled"

if [[ -n "${KLIK_INSTALLER_IDENTITY:-}" ]]; then
    PKG_PATH="${BUILD_ROOT}/${APP_NAME}-1.0.0.pkg"
    productbuild --component "${APP_BUNDLE}" /Applications \
        --sign "${KLIK_INSTALLER_IDENTITY}" "${PKG_PATH}"
    echo "✅ Upload package: ${PKG_PATH}"
fi
