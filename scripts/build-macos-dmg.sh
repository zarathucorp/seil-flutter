#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  exit 1
fi

for required_tool in flutter xcrun hdiutil codesign lipo; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    echo "Required tool not found: $required_tool" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
cd "$project_dir"

flutter config --enable-macos-desktop
flutter pub get
flutter build macos --release

version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)"
if [[ -z "$version" ]]; then
  version="dev"
fi

app_path="$project_dir/build/macos/Build/Products/Release/SEIL.app"
binary_path="$app_path/Contents/MacOS/SEIL"
output_dir="$project_dir/release/macos"
dmg_path="$output_dir/SEIL-v${version}-macos.dmg"

if [[ ! -d "$app_path" ]]; then
  echo "Built app was not found at: $app_path" >&2
  exit 1
fi

if [[ ! -f "$binary_path" ]]; then
  echo "Built executable was not found at: $binary_path" >&2
  exit 1
fi

architectures="$(lipo -archs "$binary_path")"
for required_architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $required_architecture "* ]]; then
    echo "Release executable is missing $required_architecture: $architectures" >&2
    exit 1
  fi
done
echo "Verified universal macOS executable: $architectures"

mkdir -p "$output_dir"

if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  echo "Signing SEIL.app with: $MACOS_SIGN_IDENTITY"
  codesign \
    --deep \
    --force \
    --options runtime \
    --timestamp \
    --sign "$MACOS_SIGN_IDENTITY" \
    "$app_path"
fi
codesign --verify --deep --strict --verbose=2 "$app_path"

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/seil-dmg.XXXXXX")"
cleanup() {
  rm -rf -- "$staging_dir"
}
trap cleanup EXIT

cp -R "$app_path" "$staging_dir/SEIL.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "SEIL" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"
hdiutil verify "$dmg_path"

if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$MACOS_SIGN_IDENTITY" "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"
fi

if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  if [[ -z "${MACOS_SIGN_IDENTITY:-}" ]]; then
    echo "MACOS_SIGN_IDENTITY is required when notarizing." >&2
    exit 1
  fi
  xcrun notarytool submit \
    "$dmg_path" \
    --keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE" \
    --wait
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
fi

echo "DMG created: $dmg_path"
