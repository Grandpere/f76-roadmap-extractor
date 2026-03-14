#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="F76RoadmapExtractor"
APP_NAME="F76 Roadmap Extractor"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SCRATCH_DIR="${ROOT_DIR}/.build-scratch"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"
ICON_SOURCE="${ROOT_DIR}/Sources/ocr-ui/Resources/f76logo.png"
ICON_OUTPUT="${RESOURCES_DIR}/AppIcon.icns"

mkdir -p "${DIST_DIR}"

DEVELOPER_DIR=/Library/Developer/CommandLineTools \
CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/ModuleCache" \
xcrun swift build --scratch-path "${SCRATCH_DIR}" -c release --product "${PRODUCT_NAME}"

BIN_DIR="$(
  DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/ModuleCache" \
  xcrun swift build --scratch-path "${SCRATCH_DIR}" -c release --show-bin-path
)"
EXECUTABLE_PATH="${BIN_DIR}/${PRODUCT_NAME}"

rm -rf "${APP_DIR}" "${ICONSET_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${ICONSET_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

for size in 16 32 128 256 512; do
  xcrun sips -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  xcrun sips -z "${double_size}" "${double_size}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

xcrun iconutil -c icns "${ICONSET_DIR}" -o "${ICON_OUTPUT}"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>F76 Roadmap Extractor</string>
  <key>CFBundleExecutable</key>
  <string>F76 Roadmap Extractor</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.fed76.roadmap.extractor</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>F76 Roadmap Extractor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --options runtime --sign "${SIGN_IDENTITY}" "${APP_DIR}"

touch "${APP_DIR}"

echo "App bundle created:"
echo "${APP_DIR}"
echo "Signed with identity: ${SIGN_IDENTITY}"
