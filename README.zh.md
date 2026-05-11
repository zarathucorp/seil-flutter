<p align="center">
  <img src="assets/app-logo.png" alt="SEIL 应用标志" width="140" height="140">
</p>

# SEIL: AI Agent Tmux Workspace

面向 AI Agent 工作流的移动端多会话 tmux 管理应用。

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

## 屏幕截图

<p align="center">
  <kbd><img src="assets/seil1.jpeg" width="220" alt="SEIL 应用截图 1"></kbd>
  <kbd><img src="assets/seil2.jpeg" width="220" alt="SEIL 应用截图 2"></kbd>
  <kbd><img src="assets/seil3.jpeg" width="220" alt="SEIL 应用截图 3"></kbd>
</p>

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
