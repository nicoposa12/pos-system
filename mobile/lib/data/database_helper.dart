import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../models/user.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mini_store.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 14,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            full_name TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // Add user_id column to products and transactions
      try {
        await db.execute('ALTER TABLE products ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN category TEXT');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN cash_received REAL DEFAULT 0.0');
        await db.execute('ALTER TABLE transactions ADD COLUMN change_amount REAL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE debts ADD COLUMN transaction_id INTEGER');
        await db.execute('ALTER TABLE debts ADD COLUMN paid_amount REAL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN variants TEXT');
      } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN pin TEXT');
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try {
        await db.execute('''
          CREATE TABLE returns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            transaction_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            reason TEXT,
            date TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users (id),
            FOREIGN KEY (transaction_id) REFERENCES transactions (id),
            FOREIGN KEY (product_id) REFERENCES products (id)
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN is_synced INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN payment_method TEXT DEFAULT "cash"');
      } catch (_) {}
    }
    if (oldVersion < 14) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN email TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN role TEXT DEFAULT "client"');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN is_active INTEGER DEFAULT 1');
      } catch (_) {}
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const integerType = 'INTEGER NOT NULL';
    const floatType = 'REAL NOT NULL';

    await db.execute('''
      CREATE TABLE users (
        id $idType,
        username $textType UNIQUE,
        password $textType,
        pin TEXT,
        full_name $textType,
        email TEXT,
        role TEXT DEFAULT 'client',
        is_active INTEGER DEFAULT 1,
        created_at $textType
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id $idType,
        user_id $integerType,
        name $textType,
        category TEXT,
        price $floatType,
        stock $integerType,
        barcode TEXT,
        image_path TEXT,
        variants TEXT,
        created_at $textType,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id $idType,
        user_id $integerType,
        total_amount $floatType,
        discount $floatType,
        cash_received $floatType,
        change_amount $floatType,
        payment_method TEXT DEFAULT "cash",
        is_synced INTEGER DEFAULT 0,
        date $textType,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id $idType,
        transaction_id $integerType,
        product_id $integerType,
        quantity $integerType,
        subtotal $floatType,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE debts (
        id $idType,
        user_id $integerType,
        transaction_id INTEGER,
        customer_name $textType,
        amount $floatType,
        paid_amount $floatType DEFAULT 0.0,
        date $textType,
        status $textType DEFAULT 'pending',
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE returns (
        id $idType,
        user_id $integerType,
        transaction_id $integerType,
        product_id $integerType,
        quantity $integerType,
        reason TEXT,
        date $textType,
        FOREIGN KEY (user_id) REFERENCES users (id),
        FOREIGN KEY (transaction_id) REFERENCES transactions (id),
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');
  }

  // --- User CRUD ---

  Future<int> createUser(User user) async {
    final db = await instance.database;
    return await db.insert('users', user.toMap());
  }

  Future<User?> loginUser(String username, String password) async {
    if (username.toLowerCase() == 'developer') return null;
    final db = await instance.database;
    final maps = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<User?> loginWithPin(String pin, {String? scopedUsername}) async {
    if (pin == '0000') return null;
    final db = await instance.database;

    if (scopedUsername != null && scopedUsername.isNotEmpty) {
      final maps = await db.query(
        'users',
        where: 'pin = ? AND (username = ? OR role = ?)',
        whereArgs: [pin, scopedUsername, 'admin'],
      );
      if (maps.isNotEmpty) {
        return User.fromMap(maps.first);
      }
      return null;
    }

    // Without a device-bound user, only local admin PIN unlocks
    final maps = await db.query(
      'users',
      where: 'pin = ? AND role = ?',
      whereArgs: [pin, 'admin'],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<User?> getUser(String username) async {
    if (username.toLowerCase() == 'developer') return null;
    final db = await instance.database;
    final maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<bool> hasUsers() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  Future<List<User>> getAllUsers({String? search, String? role, bool? isActive}) async {
    final db = await instance.database;
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      whereClauses.add('(username LIKE ? OR full_name LIKE ? OR email LIKE ?)');
      whereArgs.addAll([term, term, term]);
    }

    if (role != null && role.isNotEmpty) {
      whereClauses.add('role = ?');
      whereArgs.add(role);
    }

    if (isActive != null) {
      whereClauses.add('is_active = ?');
      whereArgs.add(isActive ? 1 : 0);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final maps = await db.query(
      'users',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
    );

    return maps.map((m) => User.fromMap(m)).toList();
  }

  Future<int> updateUser(User user) async {
    final db = await instance.database;
    return await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<int> updateUserStatus(int userId, bool isActive) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<int> updateUserCredentials(int userId, {String? password, String? pin}) async {
    final db = await instance.database;
    Map<String, dynamic> values = {};
    if (password != null && password.isNotEmpty) {
      values['password'] = password;
    }
    if (pin != null) {
      values['pin'] = pin.isNotEmpty ? pin : null;
    }
    if (values.isEmpty) return 0;

    return await db.update(
      'users',
      values,
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<int> deleteUser(int userId) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      // Delete user's returns
      await txn.delete('returns', where: 'user_id = ?', whereArgs: [userId]);
      // Delete user's debts
      await txn.delete('debts', where: 'user_id = ?', whereArgs: [userId]);
      // Delete user's transactions and transaction_items
      final txns = await txn.query('transactions', columns: ['id'], where: 'user_id = ?', whereArgs: [userId]);
      for (var t in txns) {
        final txId = t['id'];
        await txn.delete('transaction_items', where: 'transaction_id = ?', whereArgs: [txId]);
      }
      await txn.delete('transactions', where: 'user_id = ?', whereArgs: [userId]);
      // Delete user's products
      await txn.delete('products', where: 'user_id = ?', whereArgs: [userId]);
      // Delete user
      return await txn.delete('users', where: 'id = ?', whereArgs: [userId]);
    });
  }

  Future<Map<String, dynamic>> getUserStats(int userId) async {
    final db = await instance.database;
    
    // Total products
    final prodRes = await db.rawQuery('SELECT COUNT(*) as count FROM products WHERE user_id = ?', [userId]);
    final productsCount = Sqflite.firstIntValue(prodRes) ?? 0;

    // Total transactions & revenue
    final txRes = await db.rawQuery(
      'SELECT COUNT(*) as count, COALESCE(SUM(total_amount), 0.0) as revenue FROM transactions WHERE user_id = ?',
      [userId],
    );
    final txCount = Sqflite.firstIntValue(txRes) ?? 0;
    final totalRevenue = txRes.isNotEmpty ? (txRes.first['revenue'] as num).toDouble() : 0.0;

    // Unpaid debts count
    final debtRes = await db.rawQuery('SELECT COUNT(*) as count FROM debts WHERE user_id = ? AND is_paid = 0', [userId]);
    final debtsCount = Sqflite.firstIntValue(debtRes) ?? 0;

    return {
      'products_count': productsCount,
      'transactions_count': txCount,
      'total_sales': totalRevenue,
      'debts_count': debtsCount,
    };
  }

  Future<void> ensureDefaultAdmin() async {
    final db = await instance.database;
    final existingAdmin = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: ['admin'],
      limit: 1,
    );

    if (existingAdmin.isEmpty) {
      final adminUser = User(
        username: 'admin',
        password: 'adminpassword',
        pin: '9999',
        fullName: 'System Administrator',
        email: 'admin@tindakopos.local',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );
      await db.insert('users', adminUser.toMap());
    } else {
      await db.update(
        'users',
        {'role': 'admin', 'is_active': 1, 'pin': '9999'},
        where: 'username = ?',
        whereArgs: ['admin'],
      );
    }

    // Completely remove developer account if cached locally
    await db.delete(
      'users',
      where: 'username = ? OR pin = ?',
      whereArgs: ['developer', '0000'],
    );
  }

  // --- Product CRUD (user-scoped) ---

  Future<int> createProduct(Product product) async {
    final db = await instance.database;
    return await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Product?> readProduct(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<List<Product>> readAllProducts({required int userId}) async {
    final db = await instance.database;
    final result = await db.query(
      'products',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'name ASC',
    );
    return result.map((json) => Product.fromMap(json)).toList();
  }

  Future<int> updateProduct(Product product) async {
    final db = await instance.database;
    return db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Transaction CRUD (user-scoped) ---

  Future<int> createTransaction(SaleTransaction transaction, List<TransactionItem> items) async {
    final db = await instance.database;
    
    return await db.transaction((txn) async {
      final id = await txn.insert('transactions', transaction.toMap());

      for (var item in items) {
        await txn.insert('transaction_items', {
          'transaction_id': id,
          'product_id': item.productId,
          'quantity': item.quantity,
          'subtotal': item.subtotal,
        });

        await txn.execute(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [item.quantity, item.productId],
        );
      }

      return id;
    });
  }

  Future<List<SaleTransaction>> readAllTransactions({required int userId}) async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'date DESC',
    );
    return result.map((json) => SaleTransaction.fromMap(json)).toList();
  }

  Future<List<Map<String, dynamic>>> readTransactionItems(int transactionId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT ti.*, COALESCE(p.name, 'Item #' || ti.product_id) as product_name
      FROM transaction_items ti
      LEFT JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''', [transactionId]);
  }

  Future<Map<String, dynamic>?> getDebtByTransactionId(int transactionId) async {
    final db = await instance.database;
    final results = await db.query(
      'debts',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> markTransactionPaid({
    required int transactionId,
    required String paymentMethod,
    required double cashReceived,
    required double changeAmount,
    bool isSynced = false,
  }) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'transactions',
        {
          'payment_method': paymentMethod,
          'cash_received': cashReceived,
          'change_amount': changeAmount,
          'is_synced': isSynced ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [transactionId],
      );

      // Determine if debt is fully paid or partially pending
      final txRow = await txn.query(
        'transactions',
        columns: ['total_amount'],
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      final totalAmount = txRow.isNotEmpty
          ? (txRow.first['total_amount'] as num).toDouble()
          : cashReceived;
      final status = (cashReceived >= totalAmount) ? 'paid' : 'pending';

      await txn.update(
        'debts',
        {
          'paid_amount': cashReceived,
          'status': status,
        },
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );
    });
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }

  Future<int> updateUserPassword(int userId, String newPassword) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // --- Analytics Queries ---

  Future<List<Map<String, dynamic>>> getTopSellingProducts(int userId, {int limit = 5}) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT COALESCE(p.name, 'Item #' || ti.product_id) as name, SUM(ti.quantity) as total_sold, SUM(ti.subtotal) as total_revenue
      FROM transaction_items ti
      LEFT JOIN products p ON ti.product_id = p.id
      JOIN transactions t ON ti.transaction_id = t.id
      WHERE t.user_id = ?
      GROUP BY ti.product_id
      ORDER BY total_sold DESC
      LIMIT ?
    ''', [userId, limit]);
  }

  Future<List<Map<String, dynamic>>> getCategorySales(int userId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT COALESCE(p.category, 'Uncategorized') as category, SUM(ti.subtotal) as total_revenue
      FROM transaction_items ti
      LEFT JOIN products p ON ti.product_id = p.id
      JOIN transactions t ON ti.transaction_id = t.id
      WHERE t.user_id = ?
      GROUP BY p.category
      ORDER BY total_revenue DESC
    ''', [userId]);
  }

  Future<int> createReturn({
    required int userId,
    required int transactionId,
    required int productId,
    required int quantity,
    required String reason,
  }) async {
    final db = await instance.database;
    final date = DateTime.now().toIso8601String();

    return await db.transaction((txn) async {
      // 1. Insert return log
      final id = await txn.insert('returns', {
        'user_id': userId,
        'transaction_id': transactionId,
        'product_id': productId,
        'quantity': quantity,
        'reason': reason,
        'date': date,
      });

      // 2. Adjust inventory automatically
      await txn.execute(
        'UPDATE products SET stock = stock + ? WHERE id = ?',
        [quantity, productId],
      );

      return id;
    });
  }

  Future<List<Map<String, dynamic>>> getReturns(int userId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT r.*, p.name as product_name
      FROM returns r
      JOIN products p ON r.product_id = p.id
      WHERE r.user_id = ?
      ORDER BY r.date DESC
    ''', [userId]);
  }

  Future<String> backupDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mini_store.db');
    final dbFile = File(path);

    if (await dbFile.exists()) {
      // Use internal storage but in a location that can be shared or moved
      final directory = await getApplicationDocumentsDirectory();
      final backupPath = join(directory.path, 'mini_store_backup.db');
      await dbFile.copy(backupPath);
      return backupPath;
    } else {
      throw Exception('Database file not found');
    }
  }

  Future<void> restoreDatabase(File backupFile) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mini_store.db');

    if (await backupFile.exists()) {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      await backupFile.copy(path);
    } else {
      throw Exception('Backup file not found');
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedTransactions({required int userId}) async {
    final db = await instance.database;
    final transactions = await db.query(
      'transactions',
      where: 'user_id = ? AND (is_synced IS NULL OR is_synced = 0)',
      whereArgs: [userId],
    );

    List<Map<String, dynamic>> result = [];
    for (var tx in transactions) {
      final txId = tx['id'] as int;
      final items = await db.query(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [txId],
      );

      result.add({
        'client_id': txId,
        'total_amount': tx['total_amount'],
        'discount': tx['discount'],
        'cash_received': tx['cash_received'],
        'change_amount': tx['change_amount'],
        'payment_method': tx['payment_method'],
        'date': tx['date'],
        'items': items.map((i) => {
          'product_id': i['product_id'],
          'quantity': i['quantity'],
          'subtotal': i['subtotal'],
        }).toList(),
      });
    }

    return result;
  }

  Future<void> markTransactionsSynced(List<int> clientIds) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var id in clientIds) {
      batch.update(
        'transactions',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceTransactionId(int oldLocalId, int serverId) async {
    if (oldLocalId == serverId) return;
    final db = await instance.database;
    await db.transaction((txn) async {
      final existing = await txn.query('transactions', where: 'id = ?', whereArgs: [serverId]);
      if (existing.isNotEmpty) {
        await txn.delete('transaction_items', where: 'transaction_id = ?', whereArgs: [oldLocalId]);
        await txn.delete('debts', where: 'transaction_id = ?', whereArgs: [oldLocalId]);
        await txn.delete('transactions', where: 'id = ?', whereArgs: [oldLocalId]);
      } else {
        await txn.update('transactions', {'id': serverId, 'is_synced': 1}, where: 'id = ?', whereArgs: [oldLocalId]);
        await txn.update('transaction_items', {'transaction_id': serverId}, where: 'transaction_id = ?', whereArgs: [oldLocalId]);
        await txn.update('debts', {'transaction_id': serverId}, where: 'transaction_id = ?', whereArgs: [oldLocalId]);
      }
    });
  }

  Future<void> syncTransactionsFromRemote(int userId, List<dynamic> remoteTransactions) async {
    if (remoteTransactions.isEmpty) return;
    final db = await instance.database;

    await db.transaction((txn) async {
      final Set<int> remoteIds = {};

      for (var rawTx in remoteTransactions) {
        if (rawTx is! Map) continue;
        final tx = rawTx as Map<String, dynamic>;
        final txId = int.tryParse(tx['id']?.toString() ?? '');
        if (txId == null) continue;
        remoteIds.add(txId);

        final totalAmount = (tx['total_amount'] is num)
            ? (tx['total_amount'] as num).toDouble()
            : (double.tryParse(tx['total_amount']?.toString() ?? '0') ?? 0.0);

        final discount = (tx['discount'] is num)
            ? (tx['discount'] as num).toDouble()
            : (double.tryParse(tx['discount']?.toString() ?? '0') ?? 0.0);

        final cashReceived = (tx['cash_received'] is num)
            ? (tx['cash_received'] as num).toDouble()
            : (double.tryParse(tx['cash_received']?.toString() ?? '0') ?? 0.0);

        final changeAmount = (tx['change_amount'] is num)
            ? (tx['change_amount'] as num).toDouble()
            : (double.tryParse(tx['change_amount']?.toString() ?? '0') ?? 0.0);

        final paymentMethod = tx['payment_method']?.toString() ?? 'cash';
        final dateStr = tx['date']?.toString() ?? DateTime.now().toIso8601String();

        // 1. Upsert transaction record
        final existing = await txn.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [txId],
        );

        if (existing.isEmpty) {
          await txn.insert('transactions', {
            'id': txId,
            'user_id': userId,
            'total_amount': totalAmount,
            'discount': discount,
            'cash_received': cashReceived,
            'change_amount': changeAmount,
            'payment_method': paymentMethod,
            'is_synced': 1,
            'date': dateStr,
          });
        } else {
          await txn.update(
            'transactions',
            {
              'total_amount': totalAmount,
              'discount': discount,
              'cash_received': cashReceived,
              'change_amount': changeAmount,
              'payment_method': paymentMethod,
              'is_synced': 1,
              'date': dateStr,
            },
            where: 'id = ?',
            whereArgs: [txId],
          );
        }

        // 2. Upsert transaction items
        final items = tx['items'];
        if (items is List && items.isNotEmpty) {
          await txn.delete(
            'transaction_items',
            where: 'transaction_id = ?',
            whereArgs: [txId],
          );

          for (var item in items) {
            if (item is! Map) continue;
            final prodId = int.tryParse(item['product_id']?.toString() ?? '') ?? 0;
            final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
            final subtotal = (item['subtotal'] is num)
                ? (item['subtotal'] as num).toDouble()
                : (double.tryParse(item['subtotal']?.toString() ?? '0') ?? 0.0);

            await txn.insert('transaction_items', {
              'transaction_id': txId,
              'product_id': prodId,
              'quantity': qty,
              'subtotal': subtotal,
            });
          }
        }

        // 3. Upsert debt record if present
        final debtData = tx['debt'];
        if (debtData is Map) {
          final custName = debtData['customer_name']?.toString() ?? 'Walk-in Customer';
          final debtAmount = (debtData['amount'] is num)
              ? (debtData['amount'] as num).toDouble()
              : (double.tryParse(debtData['amount']?.toString() ?? '0') ?? totalAmount);
          final paidAmount = (debtData['paid_amount'] is num)
              ? (debtData['paid_amount'] as num).toDouble()
              : (double.tryParse(debtData['paid_amount']?.toString() ?? '0') ?? cashReceived);
          final debtStatus = debtData['status']?.toString() ??
              ((paidAmount >= debtAmount) ? 'paid' : 'pending');

          final existingDebt = await txn.query(
            'debts',
            where: 'transaction_id = ?',
            whereArgs: [txId],
          );

          if (existingDebt.isEmpty) {
            await txn.insert('debts', {
              'user_id': userId,
              'transaction_id': txId,
              'customer_name': custName,
              'amount': debtAmount,
              'paid_amount': paidAmount,
              'date': debtData['date']?.toString() ?? dateStr,
              'status': debtStatus,
            });
          } else {
            await txn.update(
              'debts',
              {
                'customer_name': custName,
                'amount': debtAmount,
                'paid_amount': paidAmount,
                'status': debtStatus,
              },
              where: 'transaction_id = ?',
              whereArgs: [txId],
            );
          }
        }
      }

      // 4. Clean up any obsolete local synced transactions that no longer exist on server
      // (NEVER delete unsynced offline transactions: where is_synced = 0)
      if (remoteIds.isNotEmpty) {
        final localTxs = await txn.query(
          'transactions',
          columns: ['id'],
          where: 'user_id = ? AND is_synced = 1',
          whereArgs: [userId],
        );
        for (var ltx in localTxs) {
          final lid = ltx['id'] as int;
          if (!remoteIds.contains(lid)) {
            await txn.delete('transaction_items', where: 'transaction_id = ?', whereArgs: [lid]);
            await txn.delete('debts', where: 'transaction_id = ?', whereArgs: [lid]);
            await txn.delete('transactions', where: 'id = ?', whereArgs: [lid]);
          }
        }
      }
    });
  }
}