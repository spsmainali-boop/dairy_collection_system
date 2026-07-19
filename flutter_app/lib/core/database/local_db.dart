import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'db_init.dart';

/// Local-first SQLite store. This is the primary source of truth for the UI.
/// Every mutable domain table has a mirror here plus a `sync_status` column,
/// and every write is also appended to `sync_queue` for the SyncService to
/// push to Supabase once connectivity is available.
///
/// NOTE: on Flutter Web, initialize sqflite with `sqflite_common_ffi_web`
/// in `main.dart` before calling LocalDb.instance.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    return openAppDatabase(_createSchema);
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE centers (
        id TEXT PRIMARY KEY,
        client_uuid TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        level TEXT NOT NULL,
        parent_center_id TEXT,
        district TEXT,
        gps_lat REAL,
        gps_lng REAL,
        settlement_cycle TEXT NOT NULL DEFAULT '15day',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE farmers (
        id TEXT PRIMARY KEY,
        client_uuid TEXT UNIQUE NOT NULL,
        farmer_code TEXT NOT NULL,
        name TEXT NOT NULL,
        mobile TEXT,
        center_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE rate_charts (
        id TEXT PRIMARY KEY,
        client_uuid TEXT UNIQUE NOT NULL,
        center_id TEXT NOT NULL,
        month TEXT NOT NULL,
        fat_min REAL NOT NULL,
        fat_max REAL NOT NULL,
        rate_per_liter REAL NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      );
    ''');

    await db.execute('''
      CREATE TABLE milk_collections (
        id TEXT PRIMARY KEY,
        client_uuid TEXT UNIQUE NOT NULL,
        farmer_id TEXT NOT NULL,
        center_id TEXT NOT NULL,
        collection_date TEXT NOT NULL,
        shift TEXT NOT NULL,
        fat REAL NOT NULL,
        snf REAL,
        quantity_liters REAL NOT NULL,
        rate_applied REAL NOT NULL,
        amount REAL NOT NULL,
        entered_by TEXT NOT NULL,
        edit_history TEXT NOT NULL DEFAULT '[]',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        client_uuid TEXT UNIQUE NOT NULL,
        farmer_id TEXT NOT NULL,
        center_id TEXT NOT NULL,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        amount_due REAL NOT NULL,
        amount_paid REAL NOT NULL,
        payment_type TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        paid_at TEXT NOT NULL DEFAULT (datetime('now')),
        sync_status TEXT NOT NULL DEFAULT 'pending'
      );
    ''');

    // Write-ahead outbox: every mutation queued here until pushed to Supabase.
    await db.execute('''
      CREATE TABLE sync_queue (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        row_client_uuid TEXT NOT NULL,
        operation TEXT NOT NULL,     -- insert | update | delete
        payload TEXT NOT NULL,       -- JSON diff/full row
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        attempts INTEGER NOT NULL DEFAULT 0
      );
    ''');

    // Cached session for offline login.
    await db.execute('''
      CREATE TABLE local_session (
        mobile TEXT PRIMARY KEY,
        pin_hash TEXT NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT NOT NULL,
        center_id TEXT,
        must_change_pin INTEGER NOT NULL DEFAULT 1,
        cached_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('CREATE INDEX idx_milk_farmer ON milk_collections(farmer_id);');
    await db.execute('CREATE INDEX idx_milk_center_date ON milk_collections(center_id, collection_date);');
  }

  /// Insert or update a row locally AND enqueue it for sync in one transaction.
  Future<void> upsertAndQueue({
    required String table,
    required Map<String, Object?> row,
    required String clientUuid,
    required String operation, // insert | update | delete
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('sync_queue', {
        'table_name': table,
        'row_client_uuid': clientUuid,
        'operation': operation,
        'payload': jsonEncode(row),
      });
    });
  }

  Future<List<Map<String, Object?>>> pendingSyncItems({int limit = 50}) async {
    final database = await db;
    return database.query('sync_queue', orderBy: 'seq ASC', limit: limit);
  }

  Future<void> clearSyncItem(int seq) async {
    final database = await db;
    await database.delete('sync_queue', where: 'seq = ?', whereArgs: [seq]);
  }

  Future<void> markSynced(String table, String clientUuid) async {
    final database = await db;
    await database.update(table, {'sync_status': 'synced'},
        where: 'client_uuid = ?', whereArgs: [clientUuid]);
  }
}
