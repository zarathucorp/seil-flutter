import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/localization/seil_error_codes.dart';
import 'package:seil_mobile/core/localization/seil_localizations.dart';

void main() {
  test('identifies a TCP socket timeout', () {
    expect(
      seilConnectionFailureMessage(
        'en',
        StateError(SeilErrorCodes.sshSocketTimeout),
      ),
      'Connection failed: TCP connection to the server timed out (30s).',
    );
  });

  test('identifies an SSH initialization timeout', () {
    expect(
      seilConnectionFailureMessage(
        'ko',
        StateError(SeilErrorCodes.sshInitializationTimeout),
      ),
      '연결 실패: TCP 연결 후 SSH 인증 또는 초기화 시간 초과 (30초)',
    );
  });

  test('keeps the generic timeout fallback', () {
    expect(
      seilConnectionFailureMessage('en', TimeoutException('timed out')),
      'Connection failed: server did not respond (30s timeout)',
    );
  });

  test('explains a rejected password authentication attempt', () {
    expect(
      seilConnectionFailureMessage(
        'ko',
        StateError(SeilErrorCodes.sshPasswordAuthenticationRejected),
      ),
      contains('비밀번호 및 keyboard-interactive 인증을 모두 거부'),
    );
  });

  test('explains a rejected private key authentication attempt', () {
    expect(
      seilConnectionFailureMessage(
        'ko',
        StateError(SeilErrorCodes.sshPrivateKeyAuthenticationRejected),
      ),
      contains('공개 키가 서버의 authorized_keys에 등록'),
    );
  });
}
