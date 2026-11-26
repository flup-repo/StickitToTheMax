#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="StickitToTheMax"
APP_VERSION="${APP_VERSION:-1.0.1}"
BUNDLE_DIR="${ROOT_DIR}/build/${APP_NAME}.app"
DMG_PATH="${ROOT_DIR}/build/${APP_NAME}-${APP_VERSION}.dmg"
STAGE_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

APP_VERSION="${APP_VERSION}" "${ROOT_DIR}/scripts/bundle.sh"

echo "Staging DMG contents..."
cp -R "${BUNDLE_DIR}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

echo "Creating ${DMG_PATH}..."
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${APP_NAME} ${APP_VERSION}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

echo ""
echo "DMG created successfully:"
ls -lh "${DMG_PATH}"
