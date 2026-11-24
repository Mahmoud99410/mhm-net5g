import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Crypto helpers used by Huawei SCRAM login.
class CryptoUtils {
  static final Random _rnd = Random.secure();

  static String randomHex(int bytes) {
    final b = List<int>.generate(bytes, (_) => _rnd.nextInt(256));
    return hex(b);
  }

  static String hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List fromHex(String h) {
    final clean = h.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static List<int> hmacSha256(List<int> key, List<int> msg) =>
      Hmac(sha256, key).convert(msg).bytes;

  static List<int> sha256Bytes(List<int> data) => sha256.convert(data).bytes;

  static String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

  /// PBKDF2-HMAC-SHA256
  static List<int> pbkdf2(List<int> password, List<int> salt, int iterations,
      [int keyLength = 32]) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength / 32).ceil();
    final out = <int>[];
    for (var block = 1; block <= blocks; block++) {
      final blockBytes = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;
      var u = hmac.convert([...salt, ...blockBytes]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
    }
    return out.sublist(0, keyLength);
  }

  /// Huawei SCRAM client proof.
  static String scramClientProof({
    required String password,
    required String saltHex,
    required int iterations,
    required String firstNonce,
    required String serverNonce,
  }) {
    final salted = pbkdf2(utf8.encode(password), fromHex(saltHex), iterations);
    final clientKey = hmacSha256(utf8.encode('Client Key'), salted);
    final storedKey = sha256Bytes(clientKey);
    final authMsg = '$firstNonce,$serverNonce,$serverNonce';
    final clientSig = hmacSha256(utf8.encode(authMsg), storedKey);
    final proof = List<int>.generate(clientKey.length, (i) => clientKey[i] ^ clientSig[i]);
    return hex(proof);
  }

  /// Legacy Huawei password_type 4 hash.
  static String legacyType4(String user, String password, String token) {
    final p1 = base64.encode(utf8.encode(sha256Hex(password)));
    final p2 = sha256Hex(user + p1 + token);
    return base64.encode(utf8.encode(p2));
  }
}
