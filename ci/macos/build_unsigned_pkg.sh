#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_PATH="${WORKSPACE_PATH:-$ROOT_DIR/Telegram-Mac.xcworkspace}"
SCHEME="${SCHEME:-Release}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.ci-build/DerivedData}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/.ci-artifacts}"
STAGE_DIR="${STAGE_DIR:-$ROOT_DIR/.ci-build/pkg-root}"
PKG_IDENTIFIER="${PKG_IDENTIFIER:-org.telegram.macos.unsigned}"
RUN_CONFIGURE_FRAMEWORKS="${RUN_CONFIGURE_FRAMEWORKS:-1}"
SKIP_BUILD="${SKIP_BUILD:-0}"
APPLY_LOCAL_PATCHES="${APPLY_LOCAL_PATCHES:-1}"
PACKAGE_BASENAME_PREFIX="${PACKAGE_BASENAME_PREFIX:-Telegram}"

PKG_SCRIPTS_DIR="$ROOT_DIR/ci/macos/pkg-scripts"
COMPONENT_PLIST="$ROOT_DIR/ci/macos/component-noversioncheck.plist"
BUILD_LOG_PATH="$ARTIFACTS_DIR/xcodebuild-release.log"
CONFIGURE_LOG_PATH="$ARTIFACTS_DIR/configure-frameworks.log"
METADATA_PATH="$ARTIFACTS_DIR/build-metadata.txt"
SHA_PATH="$ARTIFACTS_DIR/SHA256SUMS.txt"

mkdir -p "$ARTIFACTS_DIR"
mkdir -p "$(dirname "$DERIVED_DATA_PATH")"

log() {
  printf '[ci] %s\n' "$*"
}

require_file() {
  if [[ ! -f "$1" ]]; then
    printf 'Required file not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_path() {
  if [[ ! -e "$1" ]]; then
    printf 'Required path not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_path "$WORKSPACE_PATH"
require_file "$COMPONENT_PLIST"
require_file "$PKG_SCRIPTS_DIR/preinstall"

cd "$ROOT_DIR"

if [[ "$APPLY_LOCAL_PATCHES" == "1" ]]; then
  log "Applying local submodule patches"
  bash "$ROOT_DIR/ci/macos/apply_submodule_patches.sh"
else
  log "Skipping local submodule patches"
fi

if [[ "$RUN_CONFIGURE_FRAMEWORKS" == "1" ]]; then
  log "Configuring bundled frameworks"
  bash "$ROOT_DIR/scripts/configure_frameworks.sh" 2>&1 | tee "$CONFIGURE_LOG_PATH"
else
  log "Skipping scripts/configure_frameworks.sh"
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  log "Building unsigned $CONFIGURATION arm64 app"
  rm -rf "$DERIVED_DATA_PATH"
  xcodebuild build \
    -workspace "$WORKSPACE_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "$DESTINATION" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    VALIDATE_PRODUCT=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    2>&1 | tee "$BUILD_LOG_PATH"
else
  log "Skipping xcodebuild because SKIP_BUILD=1"
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Telegram.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
require_file "$INFO_PLIST"

log "Refreshing ad-hoc signature for $APP_PATH"
codesign --force --deep --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PACKAGE_BASENAME="${PACKAGE_BASENAME_PREFIX}-${SHORT_VERSION}-arm64-unsigned-r${BUNDLE_VERSION}"
PKG_PATH="$ARTIFACTS_DIR/${PACKAGE_BASENAME}.pkg"
ZIP_PATH="$ARTIFACTS_DIR/${PACKAGE_BASENAME}.zip"

log "Packaging $APP_PATH"
rm -rf "$STAGE_DIR" "$PKG_PATH" "$ZIP_PATH"
mkdir -p "$STAGE_DIR/Applications"
ditto "$APP_PATH" "$STAGE_DIR/Applications/Telegram.app"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/Applications/Telegram.app"

pkgbuild \
  --root "$STAGE_DIR" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$BUNDLE_VERSION" \
  --scripts "$PKG_SCRIPTS_DIR" \
  --component-plist "$COMPONENT_PLIST" \
  "$PKG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

{
  printf 'short_version=%s\n' "$SHORT_VERSION"
  printf 'bundle_version=%s\n' "$BUNDLE_VERSION"
  printf 'app_path=%s\n' "$APP_PATH"
  printf 'pkg_path=%s\n' "$PKG_PATH"
  printf 'zip_path=%s\n' "$ZIP_PATH"
  printf 'git_commit=%s\n' "$(git rev-parse HEAD)"
  printf 'xcode_version=%s\n' "$(xcodebuild -version | tr '\n' ' ' | sed 's/  */ /g')"
} > "$METADATA_PATH"

shasum -a 256 "$PKG_PATH" "$ZIP_PATH" > "$SHA_PATH"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'pkg_path=%s\n' "$PKG_PATH"
    printf 'zip_path=%s\n' "$ZIP_PATH"
    printf 'short_version=%s\n' "$SHORT_VERSION"
    printf 'bundle_version=%s\n' "$BUNDLE_VERSION"
  } >> "$GITHUB_OUTPUT"
fi

log "Unsigned artifacts created"
log "Package: $PKG_PATH"
log "Zip: $ZIP_PATH"
