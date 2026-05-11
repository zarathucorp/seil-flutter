#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="${AVD_NAME:-Pixel_10}"
DEVICE_SERIAL="${DEVICE_SERIAL:-emulator-5554}"
EMULATOR_MEMORY_MB="${EMULATOR_MEMORY_MB:-4096}"
CLEAN_BEFORE_RUN="${CLEAN_BEFORE_RUN:-0}"

find_android_sdk_bin() {
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local relative_path="$1"

  if [[ -n "$sdk_root" && -x "$sdk_root/$relative_path" ]]; then
    printf '%s\n' "$sdk_root/$relative_path"
    return 0
  fi

  if command -v "${relative_path##*/}" >/dev/null 2>&1; then
    command -v "${relative_path##*/}"
    return 0
  fi

  return 1
}

ADB_BIN="$(find_android_sdk_bin "platform-tools/adb")"
EMULATOR_BIN="$(find_android_sdk_bin "emulator/emulator")"

if [[ -z "${ADB_BIN:-}" || -z "${EMULATOR_BIN:-}" ]]; then
  echo "Android SDK tools not found. Set ANDROID_SDK_ROOT or ANDROID_HOME first." >&2
  exit 1
fi

cd "$ROOT_DIR"

echo "Starting adb server..."
"$ADB_BIN" start-server >/dev/null

if [[ "${CLEAN_BEFORE_RUN}" == "1" ]]; then
  echo "Cleaning Flutter build outputs..."
  flutter clean
fi

if ! "$ADB_BIN" devices | grep -q "^${DEVICE_SERIAL}[[:space:]]"; then
  echo "Launching emulator ${AVD_NAME} with ${EMULATOR_MEMORY_MB}MB RAM..."
  nohup "$EMULATOR_BIN" \
    -avd "$AVD_NAME" \
    -memory "$EMULATOR_MEMORY_MB" \
    -no-snapshot-load \
    -netdelay none \
    -netspeed full \
    >/tmp/seil-android-emulator.log 2>&1 &
fi

echo "Waiting for ${DEVICE_SERIAL}..."
"$ADB_BIN" -s "$DEVICE_SERIAL" wait-for-device
until [[ "$("$ADB_BIN" -s "$DEVICE_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  sleep 2
done

echo "Emulator booted. Running Flutter app..."
flutter run -d "$DEVICE_SERIAL" --debug
