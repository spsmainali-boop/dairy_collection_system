import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_service.dart';
import 'core/database/local_db.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/collection/bulk_collection_screen.dart';
import 'features/farmers/farmer_dashboard_screen.dart';
import 'features/farmers/farmer_pending_screen.dart';

// TODO: move these to --dart-define / a .env loaded via flutter_dotenv
// before shipping. Never commit real keys to source control.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR-PROJECT.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR-ANON-KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    await LocalDb.instance.db; // ensure schema created on startup (web uses IndexedDB automatically)
    runApp(const DairyApp());
  } catch (e, stack) {
    runApp(_StartupErrorApp(error: e.toString(), stack: stack.toString()));
  }
}

/// Shown only if something fails during app startup (bad Supabase URL/key,
/// local DB init failure, etc.) — makes the real error visible and
/// selectable/copyable instead of a blank white screen.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stack});
  final String error;
  final String stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Startup Error',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 16),
                SelectableText(error, style: const TextStyle(fontSize: 16, fontFamily: 'monospace')),
                const SizedBox(height: 16),
                const Text('Stack trace:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(stack, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DairyApp extends StatefulWidget {
  const DairyApp({super.key});
  @override
  State<DairyApp> createState() => _DairyAppState();
}

class _DairyAppState extends State<DairyApp> {
  late final AuthService _authService;
  late final SyncService _syncService;

  LoginResult? _session;
  String? _mobile;
  String? _pin; // kept only in memory, needed to re-verify farmer actions (accept/reject/disconnect)

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

  void _logout() {
    setState(() {
      _session = null;
      _mobile = null;
      _pin = null;
    });
  }

  Widget _homeForSession() {
    final session = _session!;

    if (session.role != 'farmer') {
      // Operator/admin roles land on the daily bulk-entry screen.
      return BulkCollectionScreen(
        centerId: session.centerId ?? 'CURRENT_CENTER_ID',
        enteredByUserId: session.userId,
      );
    }

    // Farmer roles: route based on connection status.
    switch (session.farmerStatus) {
      case 'pending':
        return FarmerPendingScreen(
          authService: _authService,
          mobile: _mobile!,
          pin: _pin!,
          centerName: session.farmerCenterName ?? '',
          onAccepted: () => setState(() => _session = LoginResult(
                userId: session.userId,
                mustChangePin: session.mustChangePin,
                role: session.role,
                farmerId: session.farmerId,
                farmerStatus: 'active',
                farmerCenterName: session.farmerCenterName,
              )),
          onRejected: _logout,
        );
      case 'active':
        return FarmerDashboardScreen(
          authService: _authService,
          mobile: _mobile!,
          pin: _pin!,
          farmerId: session.farmerId!,
          centerName: session.farmerCenterName ?? '',
          onDisconnected: _logout,
          onLogout: _logout,
        );
      case 'disconnected':
        return Scaffold(
          appBar: AppBar(title: const Text(Strings.appName), actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          ]),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'तपाईं हाल कुनै सक्रिय केन्द्रसँग जोडिनुभएको छैन।',
                // "You're not currently connected to any active center."
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      default:
        // Offline login for a farmer account — connection status unknown
        // without a server round-trip, so don't guess.
        return Scaffold(
          appBar: AppBar(title: const Text(Strings.appName), actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          ]),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'तपाईंको जडान स्थिति हेर्न इन्टरनेट चाहिन्छ। पछि फेरि लगइन गर्नुहोस्।',
                // "Viewing your connection status needs internet. Please log in again later."
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: _session == null
          ? LoginScreen(
              authService: _authService,
              onLoggedIn: (result, mobile, pin) {
                setState(() {
                  _session = result;
                  _mobile = mobile;
                  _pin = pin;
                });
              },
            )
          : _homeForSession(),
    );
  }
}
