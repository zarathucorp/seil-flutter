<p align="center">
  <img src="assets/app-logo.png" alt="SEIL app logo" width="140" height="140">
</p>

# SEIL: AI Agent Tmux Workspace

Mobile multi-session tmux management app for AI agent workflows.

[English](README.md) | [한국어](readmes/README.ko.md) | [日本語](readmes/README.ja.md) | [中文](readmes/README.zh.md)

## Download

Download the latest SEIL release from the [GitHub Releases page](https://github.com/zarathucorp/seil-flutter/releases).

## Screenshots

<p align="center">
  <kbd><img src="assets/seil1.jpeg" width="220" alt="SEIL app screenshot 1"></kbd>
  <kbd><img src="assets/seil2.jpeg" width="220" alt="SEIL app screenshot 2"></kbd>
  <kbd><img src="assets/seil3.jpeg" width="220" alt="SEIL app screenshot 3"></kbd>
</p>

SEIL is a Flutter mobile app for managing SSH workspaces, remote tmux sessions, and SFTP files from a phone or tablet. It is designed for developers who run AI agents, coding assistants, or long-running terminal jobs on remote servers and need a compact way to reconnect, inspect, and control those sessions.

### Features

- Save SSH connection templates locally.
- Connect with password or private-key authentication.
- Store connection secrets with platform secure storage.
- Manage multiple live SSH workspaces.
- Discover, select, create, and close remote tmux sessions.
- Use terminal controls for tmux panes, windows, scrolling, and command input.
- Browse remote files over SFTP.
- Create folders, rename files, upload/download files, and read/write text files.
- Use local app bootstrap, login, and password change flows.

Remote tmux support requires `tmux` to be installed on the target server. SSH and SFTP features require the target server to allow SSH access.

If `tmux` is missing on the server, install it with the command for your distribution.

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y tmux

# Fedora/RHEL family
sudo dnf install -y tmux

# Arch Linux
sudo pacman -S tmux
```

### Project Structure

This repository follows a standard Flutter project layout.

```text
lib/        Flutter application source
android/    Android platform project
linux/      Linux desktop platform project
web/        Web platform files
assets/     Images, fonts, and file icons
scripts/    Development helper scripts
test/       Flutter tests
```

### Flutter Build Environment

Install the usual Flutter development environment before building.

- Flutter SDK, with Dart included
- Android Studio
- Android SDK Platform Tools
- Android SDK Command-line Tools
- Android emulator or a physical Android device
- Java/JDK version compatible with the Android Gradle Plugin bundled with this Flutter project

Check the environment:

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

### Setup

```bash
git clone https://github.com/zarathucorp/seil-flutter.git
cd seil-flutter
flutter pub get
```

### Run in Debug Mode

Use any connected Android device or emulator:

```bash
flutter run
```

Or choose a specific device:

```bash
flutter devices
flutter run -d <device-id>
```

For Android emulator development, this repository includes a helper script:

```bash
./scripts/dev-android-emulator.sh
```

Optional environment variables:

```bash
AVD_NAME=Pixel_10 EMULATOR_MEMORY_MB=4096 ./scripts/dev-android-emulator.sh
CLEAN_BEFORE_RUN=1 ./scripts/dev-android-emulator.sh
```

### Build an APK

Build a release APK:

```bash
flutter build apk --release
```

The generated APK is usually located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Build a Google Play App Bundle

Closed testing on Google Play should use a release-signed Android App Bundle. Release builds intentionally fail when `android/key.properties` is missing so a debug-signed artifact is not uploaded by mistake.

If this is the first Google Play upload for this package, generate a local upload keystore:

```bash
keytool -genkeypair -v -keystore android/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create the local signing config and fill in the passwords you used:

```bash
cp android/key.properties.example android/key.properties
```

Build and verify the Google Play bundle:

```bash
./scripts/build-google-play-aab.sh
```

The generated bundle is copied to:

```text
release/google/seil-v<version>-google-play-release.aab
```

For CLI upload automation, Google Play uses a Play Developer Publishing API service account JSON key rather than an interactive Google account login. Keep the JSON key and local keystore out of git.

### Install and Run an APK

Install through Flutter:

```bash
flutter install -d <device-id>
```

Or install the built APK with `adb`:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

After installation, open SEIL from the Android launcher.

### Useful Commands

```bash
flutter clean
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
```

### License

The source code in this repository is licensed under the Apache License 2.0. Zarathu names, logos, and trademarks are not granted under the source code license except as required for reasonable attribution.
