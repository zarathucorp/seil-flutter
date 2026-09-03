import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/storage/secure_vault.dart';

void main() {
  test('macOS secure storage uses the entitlement-free legacy keychain', () {
    expect(
      SecureVault.macOsOptions.toMap()['useDataProtectionKeyChain'],
      'false',
    );
    expect(SecureVault.macOsOptions.toMap().containsKey('groupId'), isFalse);
  });
}
