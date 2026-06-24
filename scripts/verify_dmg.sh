#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/verify_dmg.sh dist/Reader-1.0.0-arm64.dmg" >&2
  exit 2
fi

DMG_PATH="$1"
MOUNT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reader-dmg.XXXXXX")"
MOUNT_POINT="$MOUNT_ROOT/mount"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet || true
  elif mount | awk -v mount_point="$MOUNT_POINT" '$3 == mount_point { found = 1 } END { exit !found }'; then
    hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force -quiet || true
  fi

  if ! mount | awk -v mount_point="$MOUNT_POINT" '$3 == mount_point { found = 1 } END { exit !found }'; then
    rm -rf "$MOUNT_ROOT"
  else
    echo "warning: could not detach DMG mount point: $MOUNT_POINT" >&2
  fi
}
trap cleanup EXIT

[[ -f "$DMG_PATH" ]] || {
  echo "error: DMG not found: $DMG_PATH" >&2
  exit 1
}

mkdir -p "$MOUNT_POINT"
ATTACH_OUTPUT="$(hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly)"
DEVICE="$(
  printf '%s\n' "$ATTACH_OUTPUT" \
    | awk -v mount_point="$MOUNT_POINT" '$NF == mount_point { print $1; found = 1; exit } END { if (!found) exit 1 }'
)" || DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/^\/dev\// { print $1; exit }')"

[[ -d "$MOUNT_POINT/Reader.app" ]] || {
  echo "error: Reader.app missing in DMG" >&2
  exit 1
}

[[ -x "$MOUNT_POINT/Reader.app/Contents/MacOS/Reader" ]] || {
  echo "error: Reader executable missing or not executable" >&2
  exit 1
}

[[ -L "$MOUNT_POINT/Applications" ]] || {
  echo "error: /Applications symlink missing in DMG" >&2
  exit 1
}

[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || {
  echo "error: Applications symlink points to $(readlink "$MOUNT_POINT/Applications")" >&2
  exit 1
}

echo "DMG OK: $DMG_PATH"
