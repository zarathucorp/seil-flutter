import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalFileOpener {
  const ExternalFileOpener();

  static const _channel = MethodChannel('com.zarathu.seil/external_file');

  Future<void> open(String path) async {
    if (!_isAndroid) {
      throw UnsupportedError(
          'External file open is only available on Android.');
    }
    try {
      await _channel.invokeMethod<void>('open', {'path': path});
    } on MissingPluginException catch (error) {
      throw StateError(
        'External file opener is not available in this app build. '
        'Install the latest Android build and try again. ($error)',
      );
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
