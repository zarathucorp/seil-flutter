# SEIL: AI Agent Tmux Workspace

Mobile multi-session tmux management app for AI agent workflows.

[English](#english) | [한국어](#한국어) | [日本語](#日本語) | [中文](#中文)

## English

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

---

## 한국어

SEIL은 휴대폰이나 태블릿에서 SSH 워크스페이스, 원격 tmux 세션, SFTP 파일을 관리하기 위한 Flutter 모바일 앱입니다. 원격 서버에서 AI 에이전트, 코딩 어시스턴트, 장시간 실행되는 터미널 작업을 운영하는 개발자가 세션에 다시 접속하고 상태를 확인하며 제어할 수 있도록 설계되었습니다.

### 주요 기능

- SSH 연결 템플릿을 로컬에 저장합니다.
- 비밀번호 또는 private key 인증으로 접속합니다.
- 연결 secret을 플랫폼 secure storage에 저장합니다.
- 여러 SSH 워크스페이스를 동시에 관리합니다.
- 원격 tmux 세션을 탐색, 선택, 생성, 종료합니다.
- tmux pane, window, 스크롤, 명령 입력을 위한 터미널 컨트롤을 제공합니다.
- SFTP로 원격 파일을 탐색합니다.
- 폴더 생성, 파일 이름 변경, 업로드/다운로드, 텍스트 파일 읽기/쓰기를 지원합니다.
- 로컬 앱 bootstrap, 로그인, 비밀번호 변경 흐름을 제공합니다.

원격 tmux 기능을 사용하려면 대상 서버에 `tmux`가 설치되어 있어야 합니다. SSH와 SFTP 기능을 사용하려면 대상 서버가 SSH 접속을 허용해야 합니다.

### 프로젝트 구조

이 저장소는 일반적인 Flutter 프로젝트 구조를 따릅니다.

```text
lib/        Flutter 애플리케이션 소스
android/    Android 플랫폼 프로젝트
linux/      Linux 데스크톱 플랫폼 프로젝트
web/        Web 플랫폼 파일
assets/     이미지, 폰트, 파일 아이콘
scripts/    개발 보조 스크립트
test/       Flutter 테스트
```

### Flutter 빌드 환경

빌드 전에 일반적인 Flutter 개발 환경을 설치합니다.

- Flutter SDK, Dart 포함
- Android Studio
- Android SDK Platform Tools
- Android SDK Command-line Tools
- Android 에뮬레이터 또는 실제 Android 기기
- 이 Flutter 프로젝트에 포함된 Android Gradle Plugin과 호환되는 Java/JDK

환경을 확인합니다.

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

### 설치

```bash
git clone https://github.com/zarathucorp/seil-flutter.git
cd seil-flutter
flutter pub get
```

### 디버그 모드 실행

연결된 Android 기기 또는 에뮬레이터에서 실행합니다.

```bash
flutter run
```

특정 기기를 선택할 수도 있습니다.

```bash
flutter devices
flutter run -d <device-id>
```

Android 에뮬레이터 개발용 보조 스크립트도 포함되어 있습니다.

```bash
./scripts/dev-android-emulator.sh
```

필요하면 환경 변수로 동작을 조절할 수 있습니다.

```bash
AVD_NAME=Pixel_10 EMULATOR_MEMORY_MB=4096 ./scripts/dev-android-emulator.sh
CLEAN_BEFORE_RUN=1 ./scripts/dev-android-emulator.sh
```

### APK 빌드

release APK를 빌드합니다.

```bash
flutter build apk --release
```

생성된 APK는 일반적으로 아래 경로에 있습니다.

```text
build/app/outputs/flutter-apk/app-release.apk
```

### APK 설치 및 실행

Flutter로 설치합니다.

```bash
flutter install -d <device-id>
```

또는 `adb`로 빌드된 APK를 설치합니다.

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

설치 후 Android 런처에서 SEIL을 실행합니다.

### 유용한 명령

```bash
flutter clean
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
```

### 라이선스

이 저장소의 소스 코드는 Apache License 2.0에 따라 라이선스가 부여됩니다. Zarathu의 이름, 로고, 상표는 합리적인 출처 표시를 위해 필요한 경우를 제외하고 소스 코드 라이선스에 포함되지 않습니다.

---

## 日本語

SEIL は、スマートフォンやタブレットから SSH ワークスペース、リモート tmux セッション、SFTP ファイルを管理するための Flutter モバイルアプリです。リモートサーバー上で AI エージェント、コーディングアシスタント、長時間実行されるターミナルジョブを扱う開発者が、セッションへ再接続し、状態を確認し、操作できるように設計されています。

### 主な機能

- SSH 接続テンプレートをローカルに保存します。
- パスワード認証または private key 認証で接続します。
- 接続 secret をプラットフォームの secure storage に保存します。
- 複数の SSH ワークスペースを同時に管理します。
- リモート tmux セッションを検出、選択、作成、終了します。
- tmux pane、window、スクロール、コマンド入力向けのターミナル操作を提供します。
- SFTP でリモートファイルを閲覧します。
- フォルダ作成、ファイル名変更、アップロード/ダウンロード、テキストファイルの読み書きをサポートします。
- ローカルアプリの bootstrap、ログイン、パスワード変更フローを提供します。

リモート tmux 機能を利用するには、対象サーバーに `tmux` がインストールされている必要があります。SSH と SFTP 機能を利用するには、対象サーバーが SSH 接続を許可している必要があります。

### プロジェクト構成

このリポジトリは一般的な Flutter プロジェクト構成に従っています。

```text
lib/        Flutter アプリケーションソース
android/    Android プラットフォームプロジェクト
linux/      Linux デスクトッププラットフォームプロジェクト
web/        Web プラットフォームファイル
assets/     画像、フォント、ファイルアイコン
scripts/    開発補助スクリプト
test/       Flutter テスト
```

### Flutter ビルド環境

ビルド前に通常の Flutter 開発環境を用意してください。

- Flutter SDK、Dart 同梱
- Android Studio
- Android SDK Platform Tools
- Android SDK Command-line Tools
- Android エミュレーターまたは実機 Android デバイス
- この Flutter プロジェクトに含まれる Android Gradle Plugin と互換性のある Java/JDK

環境を確認します。

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

### セットアップ

```bash
git clone https://github.com/zarathucorp/seil-flutter.git
cd seil-flutter
flutter pub get
```

### デバッグ実行

接続済みの Android デバイスまたはエミュレーターで実行します。

```bash
flutter run
```

特定のデバイスを指定することもできます。

```bash
flutter devices
flutter run -d <device-id>
```

Android エミュレーター開発用の補助スクリプトも含まれています。

```bash
./scripts/dev-android-emulator.sh
```

必要に応じて環境変数で動作を調整できます。

```bash
AVD_NAME=Pixel_10 EMULATOR_MEMORY_MB=4096 ./scripts/dev-android-emulator.sh
CLEAN_BEFORE_RUN=1 ./scripts/dev-android-emulator.sh
```

### APK ビルド

release APK をビルドします。

```bash
flutter build apk --release
```

生成された APK は通常、次の場所にあります。

```text
build/app/outputs/flutter-apk/app-release.apk
```

### APK のインストールと実行

Flutter でインストールします。

```bash
flutter install -d <device-id>
```

または `adb` でビルド済み APK をインストールします。

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

インストール後、Android ランチャーから SEIL を開きます。

### 便利なコマンド

```bash
flutter clean
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
```

### ライセンス

このリポジトリのソースコードは Apache License 2.0 のもとでライセンスされています。Zarathu の名称、ロゴ、商標は、合理的な帰属表示に必要な場合を除き、ソースコードライセンスには含まれません。

---

## 中文

SEIL 是一款 Flutter 移动应用，用于在手机或平板上管理 SSH 工作区、远程 tmux 会话和 SFTP 文件。它面向在远程服务器上运行 AI Agent、编码助手或长时间终端任务的开发者，帮助他们重新连接、查看状态并控制这些会话。

### 主要功能

- 在本地保存 SSH 连接模板。
- 使用密码或 private key 认证连接。
- 使用平台 secure storage 保存连接 secret。
- 同时管理多个 SSH 工作区。
- 发现、选择、创建和关闭远程 tmux 会话。
- 提供 tmux pane、window、滚动和命令输入相关的终端控制。
- 通过 SFTP 浏览远程文件。
- 支持创建文件夹、重命名文件、上传/下载文件，以及读取/写入文本文件。
- 提供本地应用 bootstrap、登录和密码修改流程。

远程 tmux 功能要求目标服务器安装 `tmux`。SSH 和 SFTP 功能要求目标服务器允许 SSH 连接。

### 项目结构

本仓库采用标准 Flutter 项目结构。

```text
lib/        Flutter 应用源码
android/    Android 平台项目
linux/      Linux 桌面平台项目
web/        Web 平台文件
assets/     图片、字体和文件图标
scripts/    开发辅助脚本
test/       Flutter 测试
```

### Flutter 构建环境

构建前请安装常规 Flutter 开发环境。

- Flutter SDK，包含 Dart
- Android Studio
- Android SDK Platform Tools
- Android SDK Command-line Tools
- Android 模拟器或 Android 真机
- 与本 Flutter 项目中 Android Gradle Plugin 兼容的 Java/JDK

检查环境：

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

### 设置

```bash
git clone https://github.com/zarathucorp/seil-flutter.git
cd seil-flutter
flutter pub get
```

### 调试运行

在已连接的 Android 设备或模拟器上运行：

```bash
flutter run
```

也可以指定设备：

```bash
flutter devices
flutter run -d <device-id>
```

仓库中还包含 Android 模拟器开发辅助脚本：

```bash
./scripts/dev-android-emulator.sh
```

可按需使用环境变量调整行为：

```bash
AVD_NAME=Pixel_10 EMULATOR_MEMORY_MB=4096 ./scripts/dev-android-emulator.sh
CLEAN_BEFORE_RUN=1 ./scripts/dev-android-emulator.sh
```

### 构建 APK

构建 release APK：

```bash
flutter build apk --release
```

生成的 APK 通常位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

### 安装并运行 APK

通过 Flutter 安装：

```bash
flutter install -d <device-id>
```

或使用 `adb` 安装已构建的 APK：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

安装后，从 Android 启动器打开 SEIL。

### 常用命令

```bash
flutter clean
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
```

### 许可证

本仓库中的源代码使用 Apache License 2.0 许可。除合理署名所需外，Zarathu 的名称、徽标和商标不包含在源代码许可中。
