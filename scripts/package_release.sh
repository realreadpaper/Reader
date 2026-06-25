#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-Reader.xcodeproj}"
SCHEME="${SCHEME:-Reader}"
CONFIGURATION="${CONFIGURATION:-Release}"
PRODUCT_NAME="${PRODUCT_NAME:-Reader}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Manual}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/package_release.sh [arm64|x86_64|universal|all]

Environment:
  VERSION=1.0.0                 Override release version.
  CODE_SIGN_IDENTITY=-          Signing identity. Defaults to ad-hoc signing.
  CODE_SIGN_STYLE=Manual        Xcode signing style.
  PROJECT_PATH=Reader.xcodeproj Xcode project path.
  SCHEME=Reader                 Xcode scheme.

Outputs:
  dist/Reader-<version>-arm64.dmg
  dist/Reader-<version>-x86_64.dmg
  dist/Reader-<version>-universal.dmg
  matching .zip files and SHA256SUMS.txt
USAGE
}

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

version_from_project() {
  local value
  value="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$ROOT_DIR/project.yml" | head -n 1)"
  printf '%s' "${value:-1.0.0}"
}

target_archs_for_flavor() {
  case "$1" in
    arm64) printf 'arm64' ;;
    x86_64) printf 'x86_64' ;;
    universal) printf 'arm64 x86_64' ;;
    *) fail "unsupported flavor: $1" ;;
  esac
}

assert_app_archs() {
  local executable="$1"
  local expected="$2"
  local actual

  [[ -x "$executable" ]] || fail "app executable not found or not executable: $executable"
  actual="$(lipo -archs "$executable")"

  for arch in $expected; do
    if [[ " $actual " != *" $arch "* ]]; then
      fail "expected architecture '$arch' in $executable, got: $actual"
    fi
  done
}

create_dmg() {
  local app_path="$1"
  local flavor="$2"
  local version="$3"
  local staging_dir="$BUILD_ROOT/dmg-$flavor"
  local dmg_path="$DIST_DIR/$PRODUCT_NAME-$version-$flavor.dmg"

  rm -rf "$staging_dir" "$dmg_path"
  mkdir -p "$staging_dir"

  ditto "$app_path" "$staging_dir/$PRODUCT_NAME.app"
  ln -s /Applications "$staging_dir/Applications"

  hdiutil create \
    -volname "$PRODUCT_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

  "$ROOT_DIR/scripts/verify_dmg.sh" "$dmg_path"
}

create_zip() {
  local app_path="$1"
  local flavor="$2"
  local version="$3"
  local zip_path="$DIST_DIR/$PRODUCT_NAME-$version-$flavor.zip"

  rm -f "$zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
}

build_flavor() {
  local flavor="$1"
  local version="$2"
  local archs
  local archive_path
  local derived_data_path
  local app_path

  archs="$(target_archs_for_flavor "$flavor")"
  archive_path="$BUILD_ROOT/archives/$PRODUCT_NAME-$flavor.xcarchive"
  derived_data_path="$BUILD_ROOT/DerivedData-$flavor"
  app_path="$DIST_DIR/$flavor/$PRODUCT_NAME.app"

  log "Build $PRODUCT_NAME $version ($flavor: $archs)"
  rm -rf "$archive_path" "$derived_data_path" "$app_path"
  mkdir -p "$BUILD_ROOT/archives" "$DIST_DIR/$flavor"

  xcodebuild archive \
    -project "$ROOT_DIR/$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    ARCHS="$archs" \
    ONLY_ACTIVE_ARCH=NO \
    SKIP_INSTALL=NO \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    CODE_SIGN_STYLE="$CODE_SIGN_STYLE"

  ditto "$archive_path/Products/Applications/$PRODUCT_NAME.app" "$app_path"
  assert_app_archs "$app_path/Contents/MacOS/$PRODUCT_NAME" "$archs"

  log "Create installable DMG ($flavor)"
  create_dmg "$app_path" "$flavor" "$version"

  log "Create ZIP ($flavor)"
  create_zip "$app_path" "$flavor" "$version"
}

write_checksums() {
  log "Write SHA256 checksums"
  (
    cd "$DIST_DIR"
    shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt
  )
}

main() {
  local requested="${1:-all}"
  local version="${VERSION:-$(version_from_project)}"
  local flavors=()

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  case "$requested" in
    arm64|x86_64|universal) flavors=("$requested") ;;
    all) flavors=(arm64 x86_64) ;;
    *) usage; fail "unknown release flavor: $requested" ;;
  esac

  require_tool xcodebuild
  require_tool hdiutil
  require_tool ditto
  require_tool lipo
  require_tool shasum

  mkdir -p "$DIST_DIR" "$BUILD_ROOT"
  rm -f "$DIST_DIR/$PRODUCT_NAME-$version-"*.dmg "$DIST_DIR/$PRODUCT_NAME-$version-"*.zip "$DIST_DIR/SHA256SUMS.txt"

  for flavor in "${flavors[@]}"; do
    build_flavor "$flavor" "$version"
  done

  write_checksums

  log "Release artifacts"
  find "$DIST_DIR" -maxdepth 1 -type f \( -name '*.dmg' -o -name '*.zip' -o -name 'SHA256SUMS.txt' \) -print | sort
}

main "$@"
