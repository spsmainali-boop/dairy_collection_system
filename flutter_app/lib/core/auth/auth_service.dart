import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_db.dart';

/// Handles mobile-number + PIN authentication.
///
/// Online: calls a Supabase Edge Function `verify-pin` which checks the PIN
/// against the bcrypt hash server-side (never sent in plaintext to the DB
/// directly) and returns a signed session. On success we cache a local-only
/// SHA-256 hash of the PIN (NOT the bcrypt hash) so the device can validate
/// login again fully offline without ever contacting the server.
///
/// Offline: if there's no connectivity, validate against `local_session`.
/// The user must have logged in online at least once on this device.
class AuthService {
  AuthService(this._supabase);
  final SupabaseClient _supabase;

  String _localHash(String pin, String mobile) {
    // Salting with the mobile number is sufficient here since this hash only
    // ever needs to protect against casual on-device tampering; the
    // authoritative check is always the server-side bcrypt hash when online.
    return sha256.convert(utf8.encode('$mobile:$pin')).toString();
  }

  /// Returns must_change_pin flag on success; throws on invalid credentials.
  Future<bool> login({required String mobile, required String pin}) async {
    try {
      final res = await _supabase.functions.invoke('verify-pin', body: {
        'mobile': mobile,
        'pin': pin,
      });
      if (res.status != 200) {
        throw AuthException('मोबाइल नम्बर वा पिन मिलेन'); // mobile/PIN mismatch
      }
      final data = res.data as Map<String, dynamic>;
      final db = await LocalDb.instance.db;
      await db.insert('local_session', {
        'mobile': mobile,
        'pin_hash': _localHash(pin, mobile),
        'user_id': data['user_id'],
        'role': data['role'],
        'center_id': data['center_id'],
        'must_change_pin': (data['must_change_pin'] == true) ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return data['must_change_pin'] == true;
    } on AuthException {
      rethrow;
    } catch (_) {
      // Network unavailable — fall back to cached local session.
      return _offlineLogin(mobile: mobile, pin: pin);
    }
  }

  Future<bool> _offlineLogin({required String mobile, required String pin}) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('local_session', where: 'mobile = ?', whereArgs: [mobile]);
    if (rows.isEmpty) {
      throw AuthException(
          'यो डिभाइसमा पहिले लगइन गरिएको छैन — इन्टरनेट जडान गरेर पहिलो पटक लगइन गर्नुहोस्.');
      // "This device hasn't logged in before — connect to the internet for first login."
    }
    final cached = rows.first;
    if (cached['pin_hash'] != _localHash(pin, mobile)) {
      throw AuthException('पिन मिलेन');
    }
    return (cached['must_change_pin'] as int) == 1;
  }

  /// Default PIN convention: last 4 digits of the mobile number. Enforced
  /// server-side at user creation (see `set_default_pin` in schema.sql); this
  /// helper exists so the client can show the expected default in onboarding UI.
  static String defaultPinFor(String mobile) =>
      mobile.length >= 4 ? mobile.substring(mobile.length - 4) : mobile;

  Future<void> changePin({required String mobile, required String newPin}) async {
    await _supabase.functions.invoke('change-pin', body: {
      'mobile': mobile,
      'new_pin': newPin,
    });
    final db = await LocalDb.instance.db;
    await db.update(
      'local_session',
      {'pin_hash': _localHash(newPin, mobile), 'must_change_pin': 0},
      where: 'mobile = ?',
      whereArgs: [mobile],
    );
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
