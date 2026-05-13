#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PROPERTIES="$ROOT_DIR/android/key.properties"
VERSION_LINE=""
SOURCE_AAB="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
DEST_DIR="$ROOT_DIR/release/google"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_key_property() {
  local key="$1"
  grep -Eq "^${key}=.+" "$KEY_PROPERTIES" || die "missing ${key} in android/key.properties"
}

require_command flutter
require_command keytool
require_command shasum

[[ -f "$KEY_PROPERTIES" ]] || die "missing android/key.properties; copy android/key.properties.example first"
require_key_property storeFile
require_key_property storePassword
require_key_property keyAlias
require_key_property keyPassword

VERSION_LINE="$(awk '/^version:/ { print $2; exit }' "$ROOT_DIR/pubspec.yaml")"
[[ -n "$VERSION_LINE" ]] || die "could not read version from pubspec.yaml"

DEST_AAB="$DEST_DIR/seil-v${VERSION_LINE}-google-play-release.aab"

cd "$ROOT_DIR"

flutter pub get
flutter analyze
flutter test
flutter build appbundle --release

[[ -f "$SOURCE_AAB" ]] || die "Flutter did not produce $SOURCE_AAB"

if keytool -printcert -jarfile "$SOURCE_AAB" | grep -q "CN=Android Debug"; then
  die "release bundle is signed with the Android debug certificate"
fi

mkdir -p "$DEST_DIR"
cp "$SOURCE_AAB" "$DEST_AAB"
shasum -a 256 "$DEST_AAB" > "$DEST_AAB.sha256.txt"

printf 'AAB: %s\n' "$DEST_AAB"
printf 'SHA256: %s\n' "$DEST_AAB.sha256.txt"
