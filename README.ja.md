<p align="center">
  <img src="assets/app-logo.png" alt="SEIL アプリロゴ" width="140" height="140">
</p>

# SEIL: AI Agent Tmux Workspace

AI エージェントワークフロー向けの、モバイル用マルチセッション tmux 管理アプリです。

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

## スクリーンショット

<p align="center">
  <kbd><img src="assets/seil1.jpeg" width="220" alt="SEIL アプリのスクリーンショット 1"></kbd>
  <kbd><img src="assets/seil2.jpeg" width="220" alt="SEIL アプリのスクリーンショット 2"></kbd>
  <kbd><img src="assets/seil3.jpeg" width="220" alt="SEIL アプリのスクリーンショット 3"></kbd>
</p>

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
