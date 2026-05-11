import 'package:flutter_test/flutter_test.dart';

import 'package:seil_mobile/app.dart';

void main() {
  test('creates the mobile app widget', () {
    expect(const SeilMobileApp(), isA<SeilMobileApp>());
  });
}
