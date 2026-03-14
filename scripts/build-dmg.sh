#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="F76 Roadmap Extractor"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_STAGING_DIR="${DIST_DIR}/dmg-root"
DMG_RW_PATH="${DIST_DIR}/${APP_NAME}-temp.dmg"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
BACKGROUND_DIR="${DMG_STAGING_DIR}/.background"
BACKGROUND_PATH="${BACKGROUND_DIR}/background.png"
VOLUME_NAME="${APP_NAME}"

"${ROOT_DIR}/scripts/build-app.sh"

hdiutil detach "/Volumes/${VOLUME_NAME}" -force >/dev/null 2>&1 || true

rm -rf "${DMG_STAGING_DIR}" "${DMG_PATH}" "${DMG_RW_PATH}"
mkdir -p "${DMG_STAGING_DIR}" "${BACKGROUND_DIR}"

cp -R "${APP_DIR}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

"${ROOT_DIR}/scripts/render-dmg-background.sh" "${BACKGROUND_PATH}"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${DMG_RW_PATH}" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_RW_PATH}")"
DEVICE="$(echo "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT_POINT="/Volumes/${VOLUME_NAME}"
DMG_MODE="styled"

if [[ -n "${DEVICE}" && -d "${MOUNT_POINT}" ]]; then
  osascript <<OSA >/dev/null 2>&1 || true
with timeout of 12 seconds
tell application "Finder"
  tell disk "${VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 920, 620}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 14
    set background picture of viewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {220, 260}
    set position of item "Applications" of container window to {580, 260}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
end timeout
OSA
fi

sync
if [[ -n "${DEVICE}" ]]; then
  hdiutil detach "${DEVICE}" -force >/dev/null || hdiutil detach "${MOUNT_POINT}" -force >/dev/null || true
fi

sleep 2

if ! hdiutil convert "${DMG_RW_PATH}" -ov -format UDZO -o "${DMG_PATH}" >/dev/null 2>&1; then
  sleep 2
  if ! hdiutil convert "${DMG_RW_PATH}" -ov -format UDZO -o "${DMG_PATH}" >/dev/null 2>&1; then
    rm -f "${DMG_PATH}"
    hdiutil create \
      -volname "${VOLUME_NAME}" \
      -srcfolder "${DMG_STAGING_DIR}" \
      -ov \
      -format UDZO \
      "${DMG_PATH}" >/dev/null
    DMG_MODE="fallback"
  fi
fi

rm -rf "${DMG_STAGING_DIR}"
rm -f "${DMG_RW_PATH}"

if [[ "${DMG_MODE}" == "styled" ]]; then
  echo "DMG created (styled):"
else
  echo "DMG created (fallback):"
fi
echo "${DMG_PATH}"
