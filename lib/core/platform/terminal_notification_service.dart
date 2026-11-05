import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TerminalNotificationLaunchTarget {
  const TerminalNotificationLaunchTarget({
    required this.connectionFingerprint,
    required this.tmuxSessionName,
    this.action,
  });

  final String connectionFingerprint;
  final String tmuxSessionName;
  final String? action;

  static TerminalNotificationLaunchTarget? fromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final connectionFingerprint = value['connectionFingerprint'];
    final tmuxSessionName = value['tmuxSessionName'];
    if (connectionFingerprint is! String ||
        connectionFingerprint.trim().isEmpty ||
        tmuxSessionName is! String ||
        tmuxSessionName.trim().isEmpty) {
      return null;
    }
    return TerminalNotificationLaunchTarget(
      connectionFingerprint: connectionFingerprint.trim(),
      tmuxSessionName: tmuxSessionName.trim(),
      action:
          value['action'] is String ? (value['action'] as String).trim() : null,
    );
  }
}

class TerminalNotificationService {
  const TerminalNotificationService({
    MethodChannel channel =
        const MethodChannel('com.zarathu.seil/terminal_notifications'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> requestPermission() async {
    if (!_isSupportedPlatform) {
      return false;
    }
    final granted = await _channel.invokeMethod<bool>('requestPermission');
    return granted ?? false;
  }

  Future<void> show({
    required int notificationId,
    required String title,
    required String body,
    required String connectionFingerprint,
    required String tmuxSessionName,
  }) {
    if (!_isSupportedPlatform) {
      return Future.value();
    }
    return _channel.invokeMethod<void>('show', {
      'notificationId': notificationId,
      'title': title,
      'body': body,
      'connectionFingerprint': connectionFingerprint,
      'tmuxSessionName': tmuxSessionName,
    });
  }

  Future<TerminalNotificationLaunchTarget?> consumeLaunchTarget() async {
    if (!_isSupportedPlatform) {
      return null;
    }
    try {
      final value = await _channel.invokeMethod<Object?>('consumeLaunchTarget');
      return TerminalNotificationLaunchTarget.fromMap(value);
    } on MissingPluginException {
      return null;
    }
  }

  void setLaunchTargetHandler(
    void Function(TerminalNotificationLaunchTarget target)? handler,
  ) {
    if (!_isSupportedPlatform) {
      return;
    }
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'notificationTapped') {
        return;
      }
      final target = TerminalNotificationLaunchTarget.fromMap(call.arguments);
      if (target != null) {
        await consumeLaunchTarget();
        handler(target);
      }
    });
  }

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
