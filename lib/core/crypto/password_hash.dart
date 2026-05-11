import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const passwordMinLength = 10;
const passwordMaxLength = 128;
final usernamePattern = RegExp(r'^[a-zA-Z0-9._@-]{3,64}$');

void assertUsername(String username) {
  if (!usernamePattern.hasMatch(username)) {
    throw ArgumentError('아이디는 3-64자의 영문, 숫자, ., _, -, @ 만 사용할 수 있습니다.');
  }
}

void assertDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > 80) {
    throw ArgumentError('이름은 1-80자로 입력해야 합니다.');
  }
}

void assertPassword(String password) {
  if (password.length < passwordMinLength || password.length > passwordMaxLength) {
    throw ArgumentError('비밀번호는 $passwordMinLength-$passwordMaxLength자로 입력해야 합니다.');
  }
}

String randomSalt([int length = 16]) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Future<String> hashPassword(String password) async {
  assertPassword(password);
  final salt = randomSalt();
  final algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );
  final secretKey = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: utf8.encode(salt),
  );
  final bytes = await secretKey.extractBytes();
  return 'pbkdf2-sha256\$210000\$$salt\$${base64UrlEncode(bytes).replaceAll('=', '')}';
}

Future<bool> verifyPassword(String password, String storedHash) async {
  final parts = storedHash.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') {
    return false;
  }

  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations <= 0) {
    return false;
  }

  final expected = _decodeBase64Url(parts[3]);
  final algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: expected.length * 8,
  );
  final secretKey = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: utf8.encode(parts[2]),
  );
  final candidate = Uint8List.fromList(await secretKey.extractBytes());
  return _constantTimeEquals(candidate, expected);
}

Uint8List _decodeBase64Url(String value) {
  final normalized = base64Url.normalize(value);
  return Uint8List.fromList(base64Url.decode(normalized));
}

bool _constantTimeEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }

  var diff = 0;
  for (var i = 0; i < left.length; i += 1) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}

