// Used on Flutter Web only, via conditional import in db_init.dart.
// sqflite on web runs on IndexedDB through sqflite_common_ffi_web, using a
// sqlite3.wasm binary + a web worker for the actual SQLite engine.
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';

Future<Database> openAppDatabase(
    Future<void> Function(Database db, int version) onCreate) async {
  databaseFactory = databaseFactoryFfiWeb;
  return databaseFactory.openDatabase(
    'dairy_collection.db',
    options: OpenDatabaseOptions(version: 1, onCreate: onCreate),
  );
}
