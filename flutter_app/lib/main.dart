import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_service.dart';
import 'core/database/local_db.dart';
import 'core/models/models.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/collection/milk_collection_screen.dart';

// TODO: move these to --dart-define / a .env loaded via flutter_dotenv
// before shipping. Never commit real keys to source control.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR-PROJECT.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR-ANON-KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await LocalDb.instance.db; // ensure schema created on startup (web uses IndexedDB automatically)

  runApp(const DairyApp());
}

class DairyApp extends StatefulWidget {
  const DairyApp({super.key});
  @override
  State<DairyApp> createState() => _DairyAppState();
}

class _DairyAppState extends State<DairyApp> {
  late final AuthService _authService;
  late final SyncService _syncService;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _authService = AuthService(client);
    _syncService = SyncService(client)..start();
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: _loggedIn
          ? MilkCollectionScreen(
              // In a full build these come from the logged-in user's session
              // (local_session table) rather than being hardcoded.
              centerId: 'CURRENT_CENTER_ID',
              enteredByUserId: 'CURRENT_USER_ID',
              getRateForFat: (fat) async {
                final db = await LocalDb.instance.db;
                final monthStart =
                    DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10);
                final rows = await db.query(
                  'rate_charts',
                  where: 'center_id = ? AND month = ? AND fat_min <= ? AND fat_max > ?',
                  whereArgs: ['CURRENT_CENTER_ID', monthStart, fat, fat],
                  limit: 1,
                );
                if (rows.isEmpty) return null; // no rate chart uploaded yet for this FAT range
                return (rows.first['rate_per_liter'] as num).toDouble();
              },
              searchFarmers: (query) async {
                final db = await LocalDb.instance.db;
                final rows = await db.query(
                  'farmers',
                  where: 'name LIKE ? OR farmer_code LIKE ?',
                  whereArgs: ['%$query%', '%$query%'],
                  limit: 20,
                );
                return rows.map((r) => Farmer.fromLocalMap(r)).toList();
              },
            )
          : LoginScreen(
              authService: _authService,
              onLoggedIn: () => setState(() => _loggedIn = true),
            ),
    );
  }
}
