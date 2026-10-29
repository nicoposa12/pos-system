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
      version: 13,
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

  Future<User?> loginWithPin(String pin) async {
    final db = await instance.database;
    final maps = await db.query(
      'users',
      where: 'pin = ?',
      whereArgs: [pin],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<User?> getUser(String username) async {
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

  // --- Product CRUD (user-scoped) ---

  Future<int> createProduct(Product product) async {
    final db = await instance.database;
    return await db.insert('products', product.toMap());
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
      SELECT ti.*, p.name as product_name
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''', [transactionId]);
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
      SELECT p.name, SUM(ti.quantity) as total_sold, SUM(ti.subtotal) as total_revenue
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
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
      SELECT p.category, SUM(ti.subtotal) as total_revenue
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
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
}