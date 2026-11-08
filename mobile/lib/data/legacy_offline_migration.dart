import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../services/api_service.dart';

/// One-time upload of data left in the retired offline SQLite store.
///
/// Earlier app versions saved sales and products locally when offline. After the
/// switch to an online-only app, this uploads any rows that never reached the
/// server for the signed-in store, then deletes the legacy database file once no
/// pending rows remain for any account. If an upload fails, the file is kept and
/// the upload is retried on the next sign-in.
class LegacyOfflineMigration {
  LegacyOfflineMigration._();

  static const _legacyDbName = 'mini_store.db';
  static bool _running = false;

  /// Returns `true` when pending legacy data was uploaded to the server.
  static Future<bool> run(int userId) async {
    if (_running || !ApiService.instance.isAuthenticated) return false;
    _running = true;
    Database? db;
    try {
      final path = join(await getDatabasesPath(), _legacyDbName);
      if (!await databaseExists(path)) return false;

      db = await openDatabase(path, singleInstance: false);
      final productIdMap = await _uploadProducts(db, userId);
      final uploadedTx = await _uploadTransactions(db, userId, productIdMap);

      if (await _remainingPending(db) == 0) {
        await db.close();
        db = null;
        await deleteDatabase(path);
        debugPrint('[LegacyOfflineMigration] Legacy offline database removed.');
      }
      return productIdMap.isNotEmpty || uploadedTx > 0;
    } catch (e) {
      debugPrint('[LegacyOfflineMigration] Upload deferred: $e');
      return false;
    } finally {
      await db?.close();
      _running = false;
    }
  }

  static Future<List<Map<String, Object?>>> _safeQuery(
    Database db,
    String sql, [
    List<Object?>? args,
  ]) async {
    try {
      return await db.rawQuery(sql, args);
    } on DatabaseException {
      // Table/column missing in very old schema versions: nothing pending there.
      return const [];
    }
  }

  /// Uploads locally created/edited products. Returns local id -> server id.
  static Future<Map<int, int>> _uploadProducts(Database db, int userId) async {
    final pending = await _safeQuery(
      db,
      'SELECT * FROM products WHERE user_id = ? AND (is_synced = 0 OR is_synced IS NULL)',
      [userId],
    );
    if (pending.isEmpty) return {};

    final payload = pending.map((p) {
      String? variants = p['variants'] as String?;
      if (variants != null) {
        try {
          if ((jsonDecode(variants) as List).isEmpty) variants = null;
        } catch (_) {
          variants = null;
        }
      }
      return {
        'client_id': p['id'],
        'name': p['name'],
        'price': p['price'],
        'stock': p['stock'],
        'category': p['category'],
        'barcode': p['barcode'],
        'variants': variants,
      };
    }).toList();

    final synced = await ApiService.instance.syncOfflineProducts(payload);
    final idMap = <int, int>{};
    for (final s in synced) {
      final clientId = int.tryParse(s['client_id']?.toString() ?? '');
      final serverId = int.tryParse(s['server_id']?.toString() ?? '');
      if (clientId != null && serverId != null) idMap[clientId] = serverId;
    }

    // Persist progress so a later retry never uploads the same rows twice.
    await db.transaction((txn) async {
      for (final entry in idMap.entries) {
        await txn.update(
          'transaction_items',
          {'product_id': entry.value},
          where: 'product_id = ?',
          whereArgs: [entry.key],
        );
        await txn.update(
          'products',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
    debugPrint('[LegacyOfflineMigration] Uploaded ${idMap.length} offline products.');
    return idMap;
  }

  /// Uploads offline sales (with debt customer names). Returns uploaded count.
  static Future<int> _uploadTransactions(
    Database db,
    int userId,
    Map<int, int> productIdMap,
  ) async {
    final pending = await _safeQuery(
      db,
      'SELECT * FROM transactions WHERE user_id = ? AND (is_synced = 0 OR is_synced IS NULL)',
      [userId],
    );
    if (pending.isEmpty) return 0;

    final payload = <Map<String, dynamic>>[];
    for (final tx in pending) {
      final txId = tx['id'] as int;
      final items = await _safeQuery(
        db,
        'SELECT product_id, quantity, subtotal FROM transaction_items WHERE transaction_id = ?',
        [txId],
      );
      final debt = await _safeQuery(
        db,
        'SELECT customer_name FROM debts WHERE transaction_id = ? LIMIT 1',
        [txId],
      );
      payload.add({
        'client_id': txId,
        'total_amount': tx['total_amount'],
        'discount': tx['discount'],
        'cash_received': tx['cash_received'],
        'change_amount': tx['change_amount'],
        'payment_method': tx['payment_method'] ?? 'cash',
        'date': tx['date'],
        'customer_name': debt.isNotEmpty ? debt.first['customer_name'] : null,
        'items': items.map((i) {
          final productId = i['product_id'] as int;
          return {
            'product_id': productIdMap[productId] ?? productId,
            'quantity': i['quantity'],
            'subtotal': i['subtotal'],
          };
        }).toList(),
      });
    }

    final synced = await ApiService.instance.syncOfflineTransactions(payload);
    final skipped = pending.length - synced.length;
    if (skipped > 0) {
      // The server skips sales whose products no longer exist for this store;
      // they can never be uploaded, so they are not retried.
      debugPrint('[LegacyOfflineMigration] $skipped offline sales referenced deleted products and were skipped.');
    }

    final pendingIds = pending.map((tx) => tx['id']).toList();
    await db.update(
      'transactions',
      {'is_synced': 1},
      where: 'id IN (${List.filled(pendingIds.length, '?').join(',')})',
      whereArgs: pendingIds,
    );
    debugPrint('[LegacyOfflineMigration] Uploaded ${synced.length} offline sales.');
    return synced.length;
  }

  /// Pending rows across all accounts that ever used this device.
  static Future<int> _remainingPending(Database db) async {
    var total = 0;
    for (final table in const ['products', 'transactions']) {
      final rows = await _safeQuery(
        db,
        'SELECT COUNT(*) AS c FROM $table WHERE is_synced = 0 OR is_synced IS NULL',
      );
      if (rows.isNotEmpty) total += (rows.first['c'] as int?) ?? 0;
    }
    return total;
  }
}

