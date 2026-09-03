import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/localization/seil_error_codes.dart';
import 'package:seil_mobile/features/sessions/ssh_session_service.dart';

const _encryptedPrivateKey = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCekzexFK
5P/Vm770y16xByAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIB1Cyx0auA6ZHEhd
xBZQqgX7coQqXTXKt984naxjj9TpAAAAoBmLebPTnO5kfJGLTF6HVgdmBG+njHxMkvS77i
FwxkZHrWkvV8bxBXFcB+Ie+zrbT1Utzm7QDsBp3st+SEacmSrh4woNRPdynRuLx0hyy3/7
57B+G2bs1BZ+/dmyiMoYSTPkLCzhkmtarvOsgJpS9Vdi9cWu/Grp+FXjRRwioQuXNAzpp5
u4j6rZMzj2304gvRvc+51dss57/fXNuCc/q9Q=
-----END OPENSSH PRIVATE KEY-----
''';

void main() {
  test('encrypted private key requires a passphrase', () {
    expect(
      () => parseSshPrivateKey(_encryptedPrivateKey, null),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          SeilErrorCodes.privateKeyPassphraseRequired,
        ),
      ),
    );
  });

  test('encrypted private key opens with the correct passphrase', () {
    final identities =
        parseSshPrivateKey(_encryptedPrivateKey, 'test-passphrase');

    expect(identities, hasLength(1));
  });

  test('encrypted private key rejects an incorrect passphrase', () {
    expect(
      () => parseSshPrivateKey(_encryptedPrivateKey, 'wrong-passphrase'),
      throwsA(anything),
    );
  });
}
