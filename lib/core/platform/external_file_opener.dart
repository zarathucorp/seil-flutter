import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalFileOpener {
  const ExternalFileOpener();

  static const _channel = MethodChannel('com.zarathu.seil/external_file');

  Future<void> open(String path) async {
    if (!_supportsOpen) {
      throw UnsupportedError(
        'External file open is only available on Android, macOS, and Windows.',
      );
    }
    await _invoke('open', path);
  }

  Future<void> reveal(String path) async {
    if (!_supportsReveal) {
      return;
    }
    await _invoke('reveal', path);
  }

  Future<void> _invoke(String method, String path) async {
    try {
      await _channel.invokeMethod<void>(method, {'path': path});
    } on MissingPluginException catch (error) {
      throw StateError(
        'External file opener is not available in this app build. '
        'Install the latest app build and try again. ($error)',
      );
    }
  }

  bool get _supportsOpen =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get _supportsReveal =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);
}
