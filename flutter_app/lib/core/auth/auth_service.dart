import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_db.dart';

/// Everything the app needs to know right after a successful login, used to
/// decide which screen to route to (operator bulk-entry, farmer dashboard,
/// or farmer pending-acceptance screen).
class LoginResult {
  final String userId;
  final bool mustChangePin;
  final String role; // 'super_admin' | 'l2_admin' | 'l1_operator' | 'l0_operator' | 'farmer'
  final String? centerId; // for operator roles
  final String? farmerId; // for role == 'farmer'
  final String? farmerStatus; // 'pending' | 'active' | 'disconnected' | null (offline/unknown)
  final String? farmerCenterName;

  LoginResult({
    required this.userId,
    required this.mustChangePin,
    required this.role,
    this.centerId,
    this.farmerId,
    this.farmerStatus,
    this.farmerCenterName,
  });
}

/// Handles mobile-number + PIN authentication.
///
/// Online: calls a Supabase Edge Function `verify-pin` which checks the PIN
/// against the bcrypt hash server-side (never sent in plaintext to the DB
/// directly) and returns a signed session. On success we cache a local-only
/// SHA-256 hash of the PIN (NOT the bcrypt hash) so the device can validate
/// login again fully offline without ever contacting the server.
///
/// Offline: if there's no connectivity, validate against `local_session`.
/// The user must have logged in online at least once on this device. Note:
/// farmer connection status (pending/active/disconnected) can only be
/// confirmed online — offline logins for farmer accounts return a null
/// farmerStatus, and the app should show a "needs internet" message rather
/// than guessing.
class AuthService {
  AuthService(this._supabase);
  final SupabaseClient _supabase;

  String _localHash(String pin, String mobile) {
    return sha256.convert(utf8.encode('$mobile:$pin')).toString();
  }

  Future<LoginResult> login({required String mobile, required String pin}) async {
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
        'user_id': data['id'],
        'role': data['role'],
        'center_id': data['center_id'],
        'must_change_pin': (data['must_change_pin'] == true) ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return LoginResult(
        userId: data['id'] as String,
        mustChangePin: data['must_change_pin'] == true,
        role: data['role'] as String,
        centerId: data['center_id'] as String?,
        farmerId: data['farmer_id'] as String?,
        farmerStatus: data['farmer_status'] as String?,
        farmerCenterName: data['farmer_center_name'] as String?,
      );
    } on AuthException {
      rethrow;
    } catch (_) {
      // Network unavailable — fall back to cached local session.
      return _offlineLogin(mobile: mobile, pin: pin);
    }
  }

  Future<LoginResult> _offlineLogin({required String mobile, required String pin}) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('local_session', where: 'mobile = ?', whereArgs: [mobile]);
    if (rows.isEmpty) {
      throw AuthException(
          'यो डिभाइसमा पहिले लगइन गरिएको छैन — इन्टरनेट जडान गरेर पहिलो पटक लगइन गर्नुहोस्.');
    }
    final cached = rows.first;
    if (cached['pin_hash'] != _localHash(pin, mobile)) {
      throw AuthException('पिन मिलेन');
    }
    return LoginResult(
      userId: cached['user_id'] as String,
      mustChangePin: (cached['must_change_pin'] as int) == 1,
      role: cached['role'] as String,
      centerId: cached['center_id'] as String?,
      // farmer connection status unknown offline — app should prompt for
      // internet rather than assume pending/active.
      farmerId: null,
      farmerStatus: null,
      farmerCenterName: null,
    );
  }

  /// Default PIN convention: last 4 digits of the mobile number. Enforced
  /// server-side at user creation; this helper exists so the client can show
  /// the expected default in onboarding UI.
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

  /// Farmer accepts or rejects a pending connection to their current center.
  Future<bool> respondToConnection({required String mobile, required String pin, required bool accept}) async {
    final res = await _supabase.functions.invoke('respond-connection', body: {
      'mobile': mobile,
      'pin': pin,
      'accept': accept,
    });
    return res.status == 200;
  }

  /// Farmer disconnects from their current center. Returns a message —
  /// either a success confirmation or the reason it was blocked (e.g. an
  /// outstanding balance).
  Future<String> disconnectFarmer({required String mobile, required String pin}) async {
    final res = await _supabase.functions.invoke('disconnect-farmer', body: {
      'mobile': mobile,
      'pin': pin,
    });
    final data = res.data as Map<String, dynamic>;
    return data['message'] as String? ?? (res.status == 200 ? 'सफल भयो' : 'त्रुटि भयो');
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
