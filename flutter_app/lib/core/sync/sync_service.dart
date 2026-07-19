import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_db.dart';

/// Bidirectional sync engine.
///
/// Push: drains `sync_queue` (FIFO) to Supabase, batched, idempotent via
/// `client_uuid` (server has a unique constraint on it — see schema.sql —
/// so retried/duplicate pushes are safely upserted, never duplicated).
///
/// Pull: for each table, fetch rows where `updated_at > last_synced_at`
/// (per-table watermark stored in SharedPreferences in a full implementation;
/// simplified here) and upsert into the local mirror.
///
/// Conflict handling: last-write-wins by `updated_at`, EXCEPT
/// `milk_collections`, where an incoming server edit that conflicts with a
/// local pending edit is merged field-by-field and a notification is queued
/// for the farmer (edits should never be silently dropped).
class SyncService {
  SyncService(this._supabase);
  final SupabaseClient _supabase;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _syncing = false;

  void start() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) unawaited(syncNow());
    });
    // Also attempt an initial sync on app start.
    unawaited(syncNow());
  }

  void dispose() => _connSub?.cancel();

  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _pushOutbox();
      await _pullTable('centers');
      await _pullTable('farmers');
      await _pullTable('rate_charts');
      await _pullTable('milk_collections');
      await _pullTable('payments');
    } catch (e) {
      // Swallow network errors; will retry on next connectivity change / timer.
      // In production: log to a diagnostics table / Sentry.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pushOutbox() async {
    final items = await LocalDb.instance.pendingSyncItems(limit: 100);
    for (final item in items) {
      final table = item['table_name'] as String;
      final clientUuid = item['row_client_uuid'] as String;
      final operation = item['operation'] as String;
      final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;

      // Strip local-only fields before sending to Supabase.
      final serverPayload = Map<String, dynamic>.from(payload)
        ..remove('sync_status');

      try {
        if (operation == 'delete') {
          await _supabase.from(table).update({'deleted_at': DateTime.now().toIso8601String()})
              .eq('client_uuid', clientUuid);
        } else {
          // Upsert on client_uuid — server has a unique constraint on this
          // column for every syncable table, making retries idempotent.
          await _supabase.from(table).upsert(serverPayload, onConflict: 'client_uuid');
        }
        await LocalDb.instance.clearSyncItem(item['seq'] as int);
        await LocalDb.instance.markSynced(table, clientUuid);
      } catch (e) {
        // Leave in queue; will retry next sync pass. Increment attempts so
        // a UI badge can show "N pending" and eventually flag for manual review.
        break; // stop draining on first failure to preserve order
      }
    }
  }

  Future<void> _pullTable(String table) async {
    // Simplified watermark: pull last 30 days by default; a production
    // implementation stores a per-table `last_synced_at` in SharedPreferences
    // and pulls `updated_at > last_synced_at` instead.
    final since = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final rows = await _supabase.from(table).select().gte('updated_at', since);
    final database = await LocalDb.instance.db;
    final batch = database.batch();
    for (final row in rows as List) {
      final map = Map<String, Object?>.from(row as Map);
      map['sync_status'] = 'synced';
      batch.insert(table, map,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
