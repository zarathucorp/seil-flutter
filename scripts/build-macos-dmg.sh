#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  exit 1
fi

for required_tool in flutter xcrun hdiutil codesign lipo plutil; do
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

variant="${SEIL_PERFORMANCE_VARIANT:-standard}"
dart_defines=()
case "$variant" in
  standard)
    app_name="SEIL"
    bundle_identifier="com.zarathu.seil"
    dmg_suffix=""
    ;;
  previous)
    app_name="SEIL Previous Test"
    bundle_identifier="com.zarathu.seil.previous-test"
    dmg_suffix="-previous-test"
    dart_defines+=(
      "--dart-define=SEIL_LEGACY_SSH_QUEUE=true"
      "--dart-define=SEIL_PERFORMANCE_TEST_LABEL=PREVIOUS"
    )
    ;;
  current)
    app_name="SEIL Current Test"
    bundle_identifier="com.zarathu.seil.current-test"
    dmg_suffix="-current-test"
    dart_defines+=(
      "--dart-define=SEIL_LEGACY_SSH_QUEUE=false"
      "--dart-define=SEIL_PERFORMANCE_TEST_LABEL=CURRENT"
    )
    ;;
  *)
    echo "Unknown SEIL_PERFORMANCE_VARIANT: $variant" >&2
    exit 1
    ;;
esac

flutter build macos --release "${dart_defines[@]}"

version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)"
if [[ -z "$version" ]]; then
  version="dev"
fi

source_app_path="$project_dir/build/macos/Build/Products/Release/SEIL.app"
output_dir="$project_dir/release/macos"
dmg_path="$output_dir/SEIL-v${version}-macos${dmg_suffix}.dmg"

if [[ ! -d "$source_app_path" ]]; then
  echo "Built app was not found at: $source_app_path" >&2
  exit 1
fi

source_binary_path="$source_app_path/Contents/MacOS/SEIL"
if [[ ! -f "$source_binary_path" ]]; then
  echo "Built executable was not found at: $source_binary_path" >&2
  exit 1
fi

architectures="$(lipo -archs "$source_binary_path")"
for required_architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $required_architecture "* ]]; then
    echo "Release executable is missing $required_architecture: $architectures" >&2
    exit 1
  fi
done
echo "Verified universal macOS executable: $architectures"

mkdir -p "$output_dir"

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/seil-dmg.XXXXXX")"
cleanup() {
  rm -rf -- "$staging_dir"
}
trap cleanup EXIT

app_path="$staging_dir/$app_name.app"
cp -R "$source_app_path" "$app_path"
plutil -replace CFBundleName -string "$app_name" "$app_path/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" \
  "$app_path/Contents/Info.plist"

if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  echo "Signing $app_name.app with: $MACOS_SIGN_IDENTITY"
  codesign \
    --deep \
    --force \
    --options runtime \
    --timestamp \
    --sign "$MACOS_SIGN_IDENTITY" \
    "$app_path"
else
  codesign --deep --force --sign - "$app_path"
fi
codesign --verify --deep --strict --verbose=2 "$app_path"
echo "Effective app entitlements:"
codesign --display --entitlements :- "$app_path"

# macOS 26 rejects some invalid or restricted entitlements only when launchd
# attempts to spawn the app. Exercise that exact path before publishing.
echo "Verifying launch through macOS Launch Services..."
open -n "$app_path"
sleep 5
if ! pgrep -x SEIL >/dev/null; then
  echo "$app_name did not remain running after Launch Services opened it." >&2
  exit 1
fi
pkill -TERM -x SEIL || true

ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "$app_name" \
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
