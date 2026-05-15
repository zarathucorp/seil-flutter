import 'package:flutter/services.dart';

class TerminalNotificationService {
  const TerminalNotificationService({
    MethodChannel channel =
        const MethodChannel('com.zarathu.seil/terminal_notifications'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> requestPermission() async {
    final granted = await _channel.invokeMethod<bool>('requestPermission');
    return granted ?? false;
  }

  Future<void> show({
    required int notificationId,
    required String title,
    required String body,
  }) {
    return _channel.invokeMethod<void>('show', {
      'notificationId': notificationId,
      'title': title,
      'body': body,
    });
  }
}
