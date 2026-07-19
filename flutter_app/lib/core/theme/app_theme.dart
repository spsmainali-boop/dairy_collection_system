import 'package:flutter/material.dart';

/// Theme tuned for rural, low-literacy, first-time-smartphone users:
/// - Large tap targets (min 56px height)
/// - High contrast colors
/// - Big, readable Nepali (Devanagari) typography
/// - Minimal visual clutter
class AppTheme {
  static const Color primaryGreen = Color(0xFF2E7D32); // trust, agriculture
  static const Color accentBlue = Color(0xFF1565C0);
  static const Color warnAmber = Color(0xFFF9A825);
  static const Color errorRed = Color(0xFFC62828);
  static const Color background = Color(0xFFF7F7F5);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          primary: primaryGreen,
          secondary: accentBlue,
          error: errorRed,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 20),
          bodyMedium: TextStyle(fontSize: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(64), // large touch target
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(fontSize: 20, color: Colors.black38),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      );
}

/// Central place for Nepali UI strings used across the app (extend as needed,
/// or replace with a full flutter_localizations / .arb setup for i18n).
class Strings {
  static const appName = 'डेयरी सङ्कलन प्रणाली';
  static const mobileNumber = 'मोबाइल नम्बर';
  static const pin = 'पिन';
  static const login = 'लगइन';
  static const changePinTitle = 'नयाँ पिन सेट गर्नुहोस्';
  static const newPin = 'नयाँ पिन';
  static const confirmPin = 'पिन पुनः लेख्नुहोस्';
  static const save = 'सुरक्षित गर्नुहोस्';
  static const morning = 'बिहान';
  static const evening = 'साँझ';
  static const fat = 'फ्याट';
  static const quantity = 'परिमाण (लिटर)';
  static const amount = 'रकम';
  static const rate = 'दर';
  static const selectFarmer = 'किसान छान्नुहोस्';
  static const scanQr = 'QR स्क्यान गर्नुहोस्';
  static const submit = 'सुरक्षित गर्नुहोस्';
  static const syncPending = 'सिंक बाँकी';
  static const synced = 'सिंक भयो';
  static const noInternet = 'इन्टरनेट छैन — पछि स्वतः सिंक हुनेछ';
}
