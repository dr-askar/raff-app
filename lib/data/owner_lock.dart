import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kept apart from product backups: restoring a file cannot reset the lock.
class OwnerLock {
  final SharedPreferences prefs;
  OwnerLock(this.prefs);
  static const _key = 'raff.owner.lock.v1';
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);
  bool get configured => prefs.containsKey(_key);
  Future<List<int>> _derive(String password, List<int> salt) async =>
    (await _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt)).extractBytes();
  Future<void> set(String password) async {
    if (password.trim().length < 6) { throw const FormatException('اختر كلمة سر من 6 أحرف أو أرقام على الأقل.'); }
    final random = Random.secure(); final salt = List.generate(32, (_) => random.nextInt(256));
    final hash = await _derive(password, salt);
    if (!await prefs.setString(_key, jsonEncode({'salt': base64Encode(salt), 'hash': base64Encode(hash)}))) {
      throw const FormatException('تعذر حفظ كلمة السر.');
    }
  }
  Future<bool> verify(String password) async {
    final saved = prefs.getString(_key); if (saved == null) { return false; }
    final data = jsonDecode(saved) as Map<String, dynamic>;
    final expected = base64Decode(data['hash'] as String);
    final actual = await _derive(password, base64Decode(data['salt'] as String));
    if (expected.length != actual.length) { return false; }
    var diff = 0; for (var i = 0; i < expected.length; i++) { diff |= expected[i] ^ actual[i]; }
    return diff == 0;
  }
}
