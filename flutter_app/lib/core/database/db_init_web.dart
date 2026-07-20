// Used on Flutter Web only, via conditional import in db_init.dart.
//
// NOTE: this uses sqflite_common's pure-Dart in-memory database factory
// instead of sqflite_common_ffi_web's worker-based IndexedDB backend.
// The worker-based approach (sqlite3.wasm + a SharedWorker) currently has a
// known compatibility bug between the package and the sqlite3.wasm version
// its own setup command downloads, producing:
//   "Unsupported operation: unsupported result null (null)"
// at runtime — see https://github.com/tekartik/sqflite/discussions/1121
//
// TRADE-OFF: web data is in-memory only and does NOT persist across a page
// refresh with this factory. Android/iOS/Desktop are unaffected — they use
// real persistent SQLite via db_init_io.dart. Revisit real IndexedDB
// persistence for web once the upstream worker issue is resolved, or by
// pinning to a known-compatible sqflite_common_ffi_web + sqlite3.wasm pair.
import 'package:sqflite_common/sqflite.dart' show databaseFactoryMemory;
import 'package:sqflite/sqflite.dart';

Future<Database> openAppDatabase(
    Future<void> Function(Database db, int version) onCreate) async {
  databaseFactory = databaseFactoryMemory;
  return databaseFactory.openDatabase(
    'dairy_collection.db',
    options: OpenDatabaseOptions(version: 1, onCreate: onCreate),
  );
}
