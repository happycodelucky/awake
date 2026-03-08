#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Awake}"
BUNDLE_ID="${BUNDLE_ID:-com.akkio.apps.awake}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-15.0}"
ARCHS=(${ARCHS:-arm64})
ADHOC_SIGN="${ADHOC_SIGN:-1}"

if xcode-select -p &>/dev/null; then
  # Active developer directory (CLT or Xcode) — use xcrun for all tools.
  SWIFTC="$(xcrun --find swiftc)"
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  SIPS="$(xcrun --find sips)"
  LIPO="$(xcrun --find lipo)"
  CODESIGN="$(xcrun --find codesign || true)"
elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  # xcode-select not configured but Xcode is installed — point at it directly.
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  SWIFTC="$(xcrun --find swiftc)"
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  SIPS="$(xcrun --find sips)"
  LIPO="$(xcrun --find lipo)"
  CODESIGN="$(xcrun --find codesign || true)"
else
  echo "Error: Xcode or Swift compiler tools are required." >&2
  echo "Install Xcode from the App Store, or run: xcode-select --install" >&2
  exit 1
fi
HOST_ARCH="$(uname -m)"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/bundle"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_GENERATOR_BIN="$BUILD_DIR/generate_app_icon"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
SOURCE_FILES=("$ROOT_DIR"/Sources/AwakeMenuBar/*.swift)
SIGN_MODE="unsigned"

mkdir -p "$DIST_DIR" "$BUILD_DIR"

if [[ -e "$APP_DIR" ]]; then
  BACKUP_PATH="$DIST_DIR/${APP_NAME}-previous-${BUILD_NUMBER}.app"
  mv "$APP_DIR" "$BACKUP_PATH"
  echo "Moved existing app bundle to $BACKUP_PATH"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

rm -f "$ZIP_PATH"
rm -f "$BUILD_DIR"/"$APP_NAME"-*
rm -f "$ICON_GENERATOR_BIN"
rm -f "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$BUILD_DIR/ModuleCache"

mkdir -p "$BUILD_DIR/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"

echo "Generating app icon..."
"$SWIFTC" \
  -sdk "$SDK_PATH" \
  -target "${HOST_ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT_DIR/scripts/generate_app_icon.swift" \
  -o "$ICON_GENERATOR_BIN"
"$ICON_GENERATOR_BIN" "$RESOURCES_DIR/AppIcon.icns"

echo "Writing Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>${DEPLOYMENT_TARGET}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

declare -a BINARIES=()
for arch in "${ARCHS[@]}"; do
  binary_path="$BUILD_DIR/${APP_NAME}-${arch}"
  BINARIES+=("$binary_path")
  echo "Compiling ${arch}..."
  "$SWIFTC" \
    -Osize \
    -parse-as-library \
    -sdk "$SDK_PATH" \
    -target "${arch}-apple-macosx${DEPLOYMENT_TARGET}" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "${SOURCE_FILES[@]}" \
    -o "$binary_path"
done

if [[ "${#BINARIES[@]}" -eq 1 ]]; then
  cp "${BINARIES[0]}" "$MACOS_DIR/$APP_NAME"
else
  echo "Creating universal binary..."
  "$LIPO" -create "${BINARIES[@]}" -output "$MACOS_DIR/$APP_NAME"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"[^"]+"/ { print $2; exit }')"
fi

if [[ -n "$SIGN_IDENTITY" ]] && [[ -n "$CODESIGN" ]]; then
  echo "Applying signature with identity: $SIGN_IDENTITY"
  "$CODESIGN" --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
  SIGN_MODE="$SIGN_IDENTITY"
elif [[ "$ADHOC_SIGN" == "1" ]] && [[ -n "$CODESIGN" ]]; then
  echo "Applying ad-hoc signature..."
  "$CODESIGN" --force --deep --sign - "$APP_DIR"
  SIGN_MODE="adhoc"
fi

echo "Creating zip archive..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Built app bundle:"
echo "  $APP_DIR"
echo "Built zip archive:"
echo "  $ZIP_PATH"
echo "Signing mode:"
echo "  $SIGN_MODE"
if [[ "$SIGN_MODE" == "unsigned" ]]; then
  echo
  echo "Note: bundle is unsigned. Set SIGN_IDENTITY or rerun with ADHOC_SIGN=1."
fi
