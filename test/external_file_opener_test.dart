import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/platform/external_file_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.zarathu.seil/external_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('macOS forwards downloaded files to the native opener', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return null;
    });

    await const ExternalFileOpener().open('/tmp/report.csv');

    expect(receivedCall?.method, 'open');
    expect(receivedCall?.arguments, {'path': '/tmp/report.csv'});
  });

  test('macOS asks Finder to reveal a downloaded file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return null;
    });

    await const ExternalFileOpener().reveal('/Users/me/Downloads/report.csv');

    expect(receivedCall?.method, 'reveal');
    expect(receivedCall?.arguments, {
      'path': '/Users/me/Downloads/report.csv',
    });
  });

  test('Windows forwards downloaded files to Explorer', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return null;
    });

    await const ExternalFileOpener()
        .reveal(r'C:\Users\me\Downloads\report.csv');

    expect(receivedCall?.method, 'reveal');
  });

  test('unsupported platforms fail before invoking a native channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      return null;
    });

    await expectLater(
      const ExternalFileOpener().open('/tmp/report.csv'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(invoked, isFalse);
  });
}
