import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocalDbService {
  static Database? _database;
  static final LocalDbService _instance = LocalDbService._internal();
  
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Initialize FFI for Windows/Linux/macOS
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    // Use a consistent path that works for both debug and MSIX
    String dbPath;
    if (Platform.isWindows) {
      // Use AppData\Local for Windows - works for both debug and MSIX
      final appData = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
      if (appData != null) {
        dbPath = join(appData, 'FiveStarChickenPOS');
        // Create directory if it doesn't exist
        final dir = Directory(dbPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        dbPath = await getDatabasesPath();
      }
    } else {
      dbPath = await getDatabasesPath();
    }
    
    final path = join(dbPath, 'five_star_pos.db');
    
    debugPrint('📦 DB path: $path');
    
    // Check current database version before opening
    try {
      final existingDb = await openDatabase(path, version: 1);
      final version = await existingDb.getVersion();
      debugPrint('📦 Current database version: $version');
      await existingDb.close();
      
      // If version is 1, we need to force upgrade
      if (version == 1) {
        debugPrint('🔄 Database needs upgrade from v1 to v2');
      }
    } catch (e) {
      debugPrint('📦 Database does not exist yet or error checking version: $e');
    }
    
    final db = await openDatabase(
      path,
      version: 2, // Updated version to trigger migration
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    // After opening, ensure all tables and columns exist
    await _ensureSchemaComplete(db);
    
    return db;
  }

  /// Ensure the database schema is complete (for cases where upgrade might not trigger)
  Future<void> _ensureSchemaComplete(Database db) async {
    try {
      // Check if raw material tables exist
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();
      
      if (!tableNames.contains('local_raw_material_stock_status')) {
        debugPrint('📦 Creating missing raw material stock tables...');
        await _createRawMaterialTables(db);
      }
      
      // Check if raw_material_mapping column exists
      final tableInfo = await db.rawQuery("PRAGMA table_info(local_products)");
      final hasColumn = tableInfo.any((column) => column['name'] == 'raw_material_mapping');
      
      if (!hasColumn) {
        debugPrint('📦 Adding missing raw_material_mapping column...');
        await db.execute('ALTER TABLE local_products ADD COLUMN raw_material_mapping TEXT');
        debugPrint('✅ Added raw_material_mapping column');
      }
      
      debugPrint('✅ Database schema is complete');
    } catch (e) {
      debugPrint('❌ Error ensuring schema completeness: $e');
    }
  }

  /// Create all base tables (used in onCreate and onUpgrade)
  Future<void> _createAllBaseTables(Database db) async {
    // Customers table (local + sync to Supabase)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL,
        store_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        customer_email TEXT,
        address TEXT,
        total_orders INTEGER DEFAULT 0,
        total_spent REAL DEFAULT 0,
        last_order_at TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Hold orders header table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hold_orders (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL,
        store_id TEXT,
        user_id TEXT NOT NULL,
        user_name TEXT,
        customer_id TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        order_type TEXT DEFAULT 'dine_in',
        table_number TEXT,
        token_number TEXT,
        sub_total REAL NOT NULL DEFAULT 0,
        discount_amount REAL DEFAULT 0,
        discount_percentage REAL DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        cgst_amount REAL DEFAULT 0,
        sgst_amount REAL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        remarks TEXT,
        hold_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // Hold order items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hold_order_items (
        id TEXT PRIMARY KEY,
        hold_order_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        item_code TEXT,
        item_name TEXT NOT NULL,
        category_name TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT DEFAULT 'PCS',
        unit_price REAL NOT NULL,
        discount_percentage REAL DEFAULT 0,
        discount_amount REAL DEFAULT 0,
        tax_percentage REAL DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        total_amount REAL NOT NULL,
        image_url TEXT,
        remarks TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (hold_order_id) REFERENCES hold_orders(id) ON DELETE CASCADE
      )
    ''');

    // Local sales orders table (offline-first)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sales_orders (
        id TEXT PRIMARY KEY,
        store_id TEXT NOT NULL,
        order_number TEXT,
        invoice_no TEXT,
        order_type TEXT DEFAULT 'dine_in',
        customer_id TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        order_date TEXT NOT NULL,
        order_time TEXT NOT NULL,
        order_timestamp TEXT NOT NULL,
        sub_total REAL NOT NULL DEFAULT 0,
        discount_amount REAL DEFAULT 0,
        discount_percentage REAL DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        cgst_amount REAL DEFAULT 0,
        sgst_amount REAL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        round_off REAL DEFAULT 0,
        final_amount REAL NOT NULL DEFAULT 0,
        payment_mode TEXT DEFAULT 'cash',
        payment_status TEXT DEFAULT 'paid',
        amount_paid REAL DEFAULT 0,
        order_status TEXT DEFAULT 'completed',
        billed_by TEXT,
        cashier_name TEXT,
        table_number TEXT,
        token_number TEXT,
        remarks TEXT,
        is_synced INTEGER DEFAULT 0,
        sync_error TEXT,
        synced_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Local sales order items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sales_order_items (
        id TEXT PRIMARY KEY,
        sales_order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        product_code TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        uom TEXT DEFAULT 'PCS',
        unit_price REAL NOT NULL,
        discount_percentage REAL DEFAULT 0,
        discount_amount REAL DEFAULT 0,
        taxable_amount REAL DEFAULT 0,
        tax_percentage REAL DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        total_line_amount REAL NOT NULL,
        line_number INTEGER DEFAULT 1,
        FOREIGN KEY (sales_order_id) REFERENCES local_sales_orders(id) ON DELETE CASCADE
      )
    ''');

    // Local products table (for offline)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_products (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL,
        category_id TEXT,
        item_code TEXT,
        item_name TEXT NOT NULL,
        short_name TEXT,
        description TEXT,
        unit TEXT DEFAULT 'PCS',
        selling_price REAL NOT NULL DEFAULT 0,
        mrp REAL,
        tax_rate REAL DEFAULT 5,
        image_url TEXT,
        barcode TEXT,
        is_veg INTEGER DEFAULT 1,
        is_available INTEGER DEFAULT 1,
        category_name TEXT,
        raw_material_mapping TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    // Local categories table (for offline)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_categories (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL,
        category_code TEXT,
        category_name TEXT NOT NULL,
        description TEXT,
        display_order INTEGER DEFAULT 0,
        image_url TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    // Create all indexes
    await _createAllIndexes(db);
    
    debugPrint('✅ All base tables created');
  }

  /// Create all indexes
  Future<void> _createAllIndexes(Database db) async {
    // Customer indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_org ON customers(org_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_phone ON customers(customer_phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_sync ON customers(is_synced)');
    
    // Hold order indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hold_org ON hold_orders(org_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hold_store ON hold_orders(store_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hold_user ON hold_orders(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hold_customer ON hold_orders(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hold_created ON hold_orders(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_holditem_order ON hold_order_items(hold_order_id)');

    // Local sales indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_sales_store ON local_sales_orders(store_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_sales_date ON local_sales_orders(order_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_sales_sync ON local_sales_orders(is_synced)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_sales_items ON local_sales_order_items(sales_order_id)');

    // Product indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_products_org ON local_products(org_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_products_category ON local_products(category_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_products_barcode ON local_products(barcode)');

    // Category indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_categories_org ON local_categories(org_id)');
  }

  /// Create raw material tables
  Future<void> _createRawMaterialTables(Database db) async {
    // Raw material stock status table (offline-first)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_raw_material_stock_status (
        id TEXT PRIMARY KEY,
        store_id TEXT NOT NULL,
        grn_item_id TEXT NOT NULL,
        material_name TEXT NOT NULL,
        material_code TEXT,
        current_stock REAL NOT NULL DEFAULT 0,
        unit TEXT DEFAULT 'PCS',
        last_updated TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(store_id, grn_item_id)
      )
    ''');

    // Stock movements table (offline-first)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_stock_movements (
        id TEXT PRIMARY KEY,
        store_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        reference_type TEXT,
        reference_id TEXT,
        quantity_before REAL NOT NULL DEFAULT 0,
        quantity_change REAL NOT NULL DEFAULT 0,
        quantity_after REAL NOT NULL DEFAULT 0,
        remarks TEXT,
        movement_date TEXT NOT NULL,
        created_by TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Indexes for stock tables
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_status_store ON local_raw_material_stock_status(store_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_status_material ON local_raw_material_stock_status(grn_item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_status_sync ON local_raw_material_stock_status(is_synced)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_store ON local_stock_movements(store_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON local_stock_movements(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_date ON local_stock_movements(movement_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_sync ON local_stock_movements(is_synced)');
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('📦 Creating database version $version');
    
    // Create all base tables
    await _createAllBaseTables(db);
    
    // If creating version 2, also create raw material tables
    if (version >= 2) {
      await _createRawMaterialTables(db);
    }
    
    debugPrint('✅ Local DB tables created');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Upgrading database from version $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // First ensure all base tables exist (in case they're missing)
      debugPrint('📦 Ensuring all base tables exist...');
      await _createAllBaseTables(db);
      
      // Add raw material stock tables in version 2
      debugPrint('📦 Adding raw material stock tables...');
      await _createRawMaterialTables(db);
      
      // Check if raw_material_mapping column exists before adding it
      final tableInfo = await db.rawQuery("PRAGMA table_info(local_products)");
      final hasColumn = tableInfo.any((column) => column['name'] == 'raw_material_mapping');
      
      if (!hasColumn) {
        try {
          await db.execute('ALTER TABLE local_products ADD COLUMN raw_material_mapping TEXT');
          debugPrint('✅ Added raw_material_mapping column to local_products');
        } catch (e) {
          debugPrint('❌ Failed to add raw_material_mapping column: $e');
        }
      } else {
        debugPrint('✅ raw_material_mapping column already exists');
      }
      
      debugPrint('✅ Database upgrade to version 2 completed');
    }
  }

  /// Ensure raw material stock tables exist (for existing databases)
  Future<void> ensureRawMaterialTablesExist() async {
    final db = await database;
    
    try {
      // Check if tables exist by trying to query them
      await db.rawQuery('SELECT COUNT(*) FROM local_raw_material_stock_status LIMIT 1');
      debugPrint('✅ Raw material stock tables already exist');
    } catch (e) {
      debugPrint('📦 Creating missing raw material stock tables...');
      await _createRawMaterialTables(db);
      debugPrint('✅ Raw material stock tables created successfully');
    }
    
    // Always ensure raw_material_mapping column exists
    try {
      final tableInfo = await db.rawQuery("PRAGMA table_info(local_products)");
      final hasColumn = tableInfo.any((column) => column['name'] == 'raw_material_mapping');
      
      if (!hasColumn) {
        await db.execute('ALTER TABLE local_products ADD COLUMN raw_material_mapping TEXT');
        debugPrint('✅ Added raw_material_mapping column to local_products');
      } else {
        debugPrint('✅ raw_material_mapping column already exists');
      }
    } catch (e) {
      debugPrint('❌ Error ensuring raw_material_mapping column: $e');
    }
  }

  // ============ HOLD ORDERS CRUD ============

  /// Save a new hold order with items
  Future<String> saveHoldOrder(HoldOrder order) async {
    final db = await database;
    
    await db.transaction((txn) async {
      // Insert header
      await txn.insert('hold_orders', order.toMap());
      
      // Insert items
      for (var item in order.items) {
        await txn.insert('hold_order_items', item.toMap());
      }
    });
    
    debugPrint('✅ Hold order saved: ${order.id}');
    return order.id;
  }

  /// Get all hold orders for an organization
  Future<List<HoldOrder>> getHoldOrders(String orgId, {String? storeId}) async {
    final db = await database;
    
    String where = 'org_id = ?';
    List<dynamic> whereArgs = [orgId];
    
    if (storeId != null) {
      where += ' AND store_id = ?';
      whereArgs.add(storeId);
    }
    
    final orderMaps = await db.query(
      'hold_orders',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    
    List<HoldOrder> orders = [];
    for (var orderMap in orderMaps) {
      final items = await db.query(
        'hold_order_items',
        where: 'hold_order_id = ?',
        whereArgs: [orderMap['id']],
      );
      
      orders.add(HoldOrder.fromMap(orderMap, items));
    }
    
    debugPrint('📋 Hold orders: ${orders.length}');
    return orders;
  }

  /// Get a single hold order by ID
  Future<HoldOrder?> getHoldOrder(String orderId) async {
    final db = await database;
    
    final orderMaps = await db.query(
      'hold_orders',
      where: 'id = ?',
      whereArgs: [orderId],
    );
    
    if (orderMaps.isEmpty) return null;
    
    final items = await db.query(
      'hold_order_items',
      where: 'hold_order_id = ?',
      whereArgs: [orderId],
    );
    
    return HoldOrder.fromMap(orderMaps.first, items);
  }

  /// Delete a hold order
  Future<void> deleteHoldOrder(String orderId) async {
    final db = await database;
    
    await db.transaction((txn) async {
      await txn.delete('hold_order_items', where: 'hold_order_id = ?', whereArgs: [orderId]);
      await txn.delete('hold_orders', where: 'id = ?', whereArgs: [orderId]);
    });
    
    debugPrint('🗑️ Hold order deleted: $orderId');
  }

  /// Get hold orders count
  Future<int> getHoldOrdersCount(String orgId, {String? storeId}) async {
    final db = await database;
    
    String where = 'org_id = ?';
    List<dynamic> whereArgs = [orgId];
    
    if (storeId != null) {
      where += ' AND store_id = ?';
      whereArgs.add(storeId);
    }
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM hold_orders WHERE $where',
      whereArgs,
    );
    
    return result.first['count'] as int? ?? 0;
  }

  // ============ CUSTOMERS CRUD ============

  /// Save or update a customer
  Future<String> saveCustomer(Customer customer) async {
    final db = await database;
    
    // Check if customer with same phone exists
    if (customer.customerPhone != null && customer.customerPhone!.isNotEmpty) {
      final existing = await db.query(
        'customers',
        where: 'org_id = ? AND customer_phone = ?',
        whereArgs: [customer.orgId, customer.customerPhone],
      );
      
      if (existing.isNotEmpty) {
        // Update existing customer
        final existingId = existing.first['id'] as String;
        await db.update(
          'customers',
          {
            'customer_name': customer.customerName,
            'updated_at': DateTime.now().toIso8601String(),
            'is_synced': 0,
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );
        debugPrint('✅ Customer updated: $existingId');
        return existingId;
      }
    }
    
    // Insert new customer
    await db.insert('customers', customer.toMap());
    debugPrint('✅ Customer saved: ${customer.id}');
    return customer.id;
  }

  /// Find customer by phone
  Future<Customer?> findCustomerByPhone(String orgId, String phone) async {
    final db = await database;
    
    final result = await db.query(
      'customers',
      where: 'org_id = ? AND customer_phone = ?',
      whereArgs: [orgId, phone],
    );
    
    if (result.isEmpty) return null;
    return Customer.fromMap(result.first);
  }

  /// Get all customers for org
  Future<List<Customer>> getCustomers(String orgId, {String? searchQuery}) async {
    final db = await database;
    
    String where = 'org_id = ?';
    List<dynamic> whereArgs = [orgId];
    
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where += ' AND (customer_name LIKE ? OR customer_phone LIKE ?)';
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }
    
    final result = await db.query(
      'customers',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'customer_name ASC',
      limit: 50,
    );
    
    return result.map((m) => Customer.fromMap(m)).toList();
  }

  /// Get unsynced customers
  Future<List<Customer>> getUnsyncedCustomers() async {
    final db = await database;
    
    final result = await db.query(
      'customers',
      where: 'is_synced = 0',
    );
    
    return result.map((m) => Customer.fromMap(m)).toList();
  }

  /// Mark customer as synced
  Future<void> markCustomerSynced(String customerId) async {
    final db = await database;
    
    await db.update(
      'customers',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  /// Delete customer from local database
  Future<void> deleteCustomer(String customerId) async {
    final db = await database;
    
    await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
    );
    
    debugPrint('🗑️ Deleted customer from local DB: $customerId');
  }

  // ============ LOCAL SALES ORDERS ============

  /// Save a sales order locally (offline-first)
  Future<String> saveLocalSalesOrder(LocalSalesOrder order) async {
    final db = await database;
    
    await db.transaction((txn) async {
      await txn.insert('local_sales_orders', order.toMap());
      
      for (var item in order.items) {
        await txn.insert('local_sales_order_items', item.toMap());
      }
    });
    
    debugPrint('✅ Local order saved: ${order.invoiceNo}');
    return order.id;
  }

  /// Get unsynced sales orders
  Future<List<LocalSalesOrder>> getUnsyncedSalesOrders() async {
    final db = await database;
    
    final orderMaps = await db.query(
      'local_sales_orders',
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );
    
    List<LocalSalesOrder> orders = [];
    for (var orderMap in orderMaps) {
      final items = await db.query(
        'local_sales_order_items',
        where: 'sales_order_id = ?',
        whereArgs: [orderMap['id']],
      );
      orders.add(LocalSalesOrder.fromMap(orderMap, items));
    }
    
    return orders;
  }

  /// Get unsynced orders count
  Future<int> getUnsyncedOrdersCount() async {
    final db = await database;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM local_sales_orders WHERE is_synced = 0',
    );
    
    return result.first['count'] as int? ?? 0;
  }

  /// Mark sales order as synced
  Future<void> markSalesOrderSynced(String orderId) async {
    final db = await database;
    
    await db.update(
      'local_sales_orders',
      {
        'is_synced': 1,
        'synced_at': DateTime.now().toIso8601String(),
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  /// Update local order invoice number (used when syncing with conflict)
  Future<void> updateLocalOrderInvoice(String orderId, String newInvoiceNo) async {
    final db = await database;
    
    await db.update(
      'local_sales_orders',
      {'invoice_no': newInvoiceNo},
      where: 'id = ?',
      whereArgs: [orderId],
    );
    debugPrint('📝 Updated local order invoice: $newInvoiceNo');
  }

  /// Mark sales order sync failed
  Future<void> markSalesOrderSyncFailed(String orderId, String error) async {
    final db = await database;
    
    await db.update(
      'local_sales_orders',
      {'sync_error': error},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  /// Get local orders by date range (for offline viewing)
  Future<List<LocalSalesOrder>> getLocalOrdersByDateRange(String storeId, DateTime fromDate, DateTime toDate) async {
    final db = await database;
    
    final fromStr = fromDate.toIso8601String().split('T')[0];
    final toStr = toDate.toIso8601String().split('T')[0];
    
    final orderMaps = await db.query(
      'local_sales_orders',
      where: 'store_id = ? AND order_date >= ? AND order_date <= ?',
      whereArgs: [storeId, fromStr, toStr],
      orderBy: 'order_timestamp DESC',
    );
    
    List<LocalSalesOrder> orders = [];
    for (var orderMap in orderMaps) {
      final items = await db.query(
        'local_sales_order_items',
        where: 'sales_order_id = ?',
        whereArgs: [orderMap['id']],
      );
      orders.add(LocalSalesOrder.fromMap(orderMap, items));
    }
    
    return orders;
  }

  /// Get a single local order by ID
  Future<LocalSalesOrder?> getLocalOrderById(String orderId) async {
    final db = await database;
    
    final orderMaps = await db.query(
      'local_sales_orders',
      where: 'id = ?',
      whereArgs: [orderId],
    );
    
    if (orderMaps.isEmpty) return null;
    
    final items = await db.query(
      'local_sales_order_items',
      where: 'sales_order_id = ?',
      whereArgs: [orderId],
    );
    
    return LocalSalesOrder.fromMap(orderMaps.first, items);
  }

  /// Generate local invoice number - checks both local DB and Supabase
  Future<String> generateLocalInvoiceNumber(String storeId) async {
    final db = await database;
    final today = DateTime.now();
    final dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final todayStr = today.toIso8601String().split('T')[0];
    
    // Get local count
    final localResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM local_sales_orders WHERE store_id = ? AND order_date = ?",
      [storeId, todayStr],
    );
    final localCount = (localResult.first['count'] as int?) ?? 0;
    
    // Try to get cloud count if online
    int cloudCount = 0;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        // Online - check Supabase for today's orders
        final supabase = Supabase.instance.client;
        final cloudResult = await supabase
            .from('sales_orders')
            .select('id')
            .eq('store_id', storeId)
            .eq('order_date', todayStr)
            .count();
        cloudCount = cloudResult.count ?? 0;
      }
    } catch (_) {
      // Offline - use local count only
    }
    
    // Use the higher of local or cloud count + 1
    final count = (localCount > cloudCount ? localCount : cloudCount) + 1;
    return 'INV-$dateStr-${count.toString().padLeft(4, '0')}';
  }

  // ============ LOCAL PRODUCTS (OFFLINE) ============

  /// Save or update a local product
  Future<void> saveLocalProduct(LocalProduct product) async {
    final db = await database;
    
    await db.insert(
      'local_products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get local products count
  Future<int> getLocalProductsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM local_products');
    return result.first['count'] as int? ?? 0;
  }

  /// Get local customers count
  Future<int> getLocalCustomersCount(String orgId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE org_id = ?',
      [orgId],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Get local products for offline use
  Future<List<LocalProduct>> getLocalProducts(String orgId, {String? categoryId, String? searchQuery}) async {
    final db = await database;
    
    String where = 'org_id = ? AND is_available = 1';
    List<dynamic> whereArgs = [orgId];
    
    if (categoryId != null) {
      where += ' AND category_id = ?';
      whereArgs.add(categoryId);
    }
    
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where += ' AND (item_name LIKE ? OR item_code LIKE ? OR barcode LIKE ?)';
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }
    
    final result = await db.query(
      'local_products',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'item_name ASC',
    );
    
    return result.map((m) => LocalProduct.fromMap(m)).toList();
  }

  /// Get product by barcode (offline)
  Future<LocalProduct?> getProductByBarcode(String orgId, String barcode) async {
    final db = await database;
    
    final result = await db.query(
      'local_products',
      where: 'org_id = ? AND barcode = ?',
      whereArgs: [orgId, barcode],
      limit: 1,
    );
    
    if (result.isEmpty) return null;
    return LocalProduct.fromMap(result.first);
  }

  // ============ LOCAL CATEGORIES (OFFLINE) ============

  /// Save or update a local category
  Future<void> saveLocalCategory(LocalCategory category) async {
    final db = await database;
    
    await db.insert(
      'local_categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get local categories count
  Future<int> getLocalCategoriesCount(String orgId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM local_categories WHERE org_id = ?',
      [orgId],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Get local categories for offline use
  Future<List<LocalCategory>> getLocalCategories(String orgId) async {
    final db = await database;
    
    final result = await db.query(
      'local_categories',
      where: 'org_id = ?',
      whereArgs: [orgId],
      orderBy: 'display_order ASC, category_name ASC',
    );
    
    return result.map((m) => LocalCategory.fromMap(m)).toList();
  }

  /// Save or update customer (for sync)
  Future<void> saveOrUpdateCustomer(Customer customer) async {
    final db = await database;
    
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get count of products with raw material mapping
  Future<int> getProductsWithMappingCount(String orgId) async {
    try {
      final db = await database;
      
      // First ensure the column exists
      await ensureRawMaterialTablesExist();
      
      // Check if the column exists
      final tableInfo = await db.rawQuery("PRAGMA table_info(local_products)");
      final hasColumn = tableInfo.any((column) => column['name'] == 'raw_material_mapping');
      
      if (!hasColumn) {
        debugPrint('⚠️ raw_material_mapping column does not exist yet');
        return 0;
      }
      
      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM local_products WHERE org_id = ? AND raw_material_mapping IS NOT NULL AND raw_material_mapping != ''",
        [orgId]
      );
      
      final count = result.first['count'] as int? ?? 0;
      debugPrint('📊 Products with raw material mapping: $count');
      return count;
    } catch (e) {
      debugPrint('❌ Error getting products with mapping count: $e');
      return 0;
    }
  }

  /// Debug: Check raw material mapping in local products
  Future<void> debugLocalProductMappings(String orgId) async {
    final db = await database;
    
    final result = await db.query(
      'local_products',
      where: 'org_id = ?',
      whereArgs: [orgId],
    );
    
    debugPrint('🔍 DEBUG: Local products raw material mapping status:');
    for (final product in result) {
      final mapping = product['raw_material_mapping'] as String?;
      if (mapping != null && mapping.isNotEmpty) {
        try {
          final parsed = jsonDecode(mapping) as List;
          debugPrint('✅ ${product['item_name']}: ${parsed.length} mappings');
        } catch (e) {
          debugPrint('❌ ${product['item_name']}: Invalid JSON - $e');
        }
      } else {
        debugPrint('⚠️ ${product['item_name']}: No mapping data');
      }
    }
  }

  /// Force database recreation (for development/testing)
  Future<void> recreateDatabase() async {
    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      
      // Get database path
      String dbPath;
      if (Platform.isWindows) {
        final appData = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
        if (appData != null) {
          dbPath = join(appData, 'FiveStarChickenPOS');
        } else {
          dbPath = await getDatabasesPath();
        }
      } else {
        dbPath = await getDatabasesPath();
      }
      
      final path = join(dbPath, 'five_star_pos.db');
      
      // Delete existing database
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ Deleted existing database: $path');
      }
      
      // Reinitialize database
      _database = await _initDatabase();
      debugPrint('✅ Database recreated successfully');
    } catch (e) {
      debugPrint('❌ Error recreating database: $e');
    }
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ============ RAW MATERIAL STOCK METHODS ============

  /// Get raw material stock status
  Future<Map<String, dynamic>?> getRawMaterialStock(String storeId, String materialId) async {
    final db = await database;
    
    final result = await db.query(
      'local_raw_material_stock_status',
      where: 'store_id = ? AND grn_item_id = ?',
      whereArgs: [storeId, materialId],
    );
    
    return result.isNotEmpty ? result.first : null;
  }

  /// Update raw material stock
  Future<void> updateRawMaterialStock({
    required String storeId,
    required String materialId,
    required String materialName,
    required String materialCode,
    required double currentStock,
    required String unit,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    
    await db.insert(
      'local_raw_material_stock_status',
      {
        'id': '$storeId-$materialId',
        'store_id': storeId,
        'grn_item_id': materialId,
        'material_name': materialName,
        'material_code': materialCode,
        'current_stock': currentStock,
        'unit': unit,
        'last_updated': now,
        'is_synced': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Record stock movement
  Future<void> recordStockMovement({
    required String id,
    required String storeId,
    required String productId,
    required String movementType,
    String? referenceType,
    String? referenceId,
    required double quantityBefore,
    required double quantityChange,
    required double quantityAfter,
    String? remarks,
    String? createdBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    
    await db.insert('local_stock_movements', {
      'id': id,
      'store_id': storeId,
      'product_id': productId,
      'movement_type': movementType,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'quantity_before': quantityBefore,
      'quantity_change': quantityChange,
      'quantity_after': quantityAfter,
      'remarks': remarks,
      'movement_date': now,
      'created_by': createdBy,
      'is_synced': 0,
      'created_at': now,
    });
  }

  /// Get unsynced stock movements
  Future<List<Map<String, dynamic>>> getUnsyncedStockMovements() async {
    final db = await database;
    
    return await db.query(
      'local_stock_movements',
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// Mark stock movement as synced
  Future<void> markStockMovementSynced(String movementId) async {
    final db = await database;
    
    await db.update(
      'local_stock_movements',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [movementId],
    );
  }

  /// Get unsynced raw material stock updates
  Future<List<Map<String, dynamic>>> getUnsyncedRawMaterialStock() async {
    final db = await database;
    
    return await db.query(
      'local_raw_material_stock_status',
      where: 'is_synced = 0',
    );
  }

  /// Mark raw material stock as synced
  Future<void> markRawMaterialStockSynced(String storeId, String materialId) async {
    final db = await database;
    
    await db.update(
      'local_raw_material_stock_status',
      {'is_synced': 1},
      where: 'store_id = ? AND grn_item_id = ?',
      whereArgs: [storeId, materialId],
    );
  }

  /// Sync raw material stock from cloud
  Future<void> syncRawMaterialStockFromCloud(String storeId) async {
    try {
      final supabase = Supabase.instance.client;
      final stockData = await supabase
          .from('raw_material_stock_status')
          .select('*')
          .eq('store_id', storeId);

      final db = await database;
      
      for (final stock in stockData) {
        await db.insert(
          'local_raw_material_stock_status',
          {
            'id': '${stock['store_id']}-${stock['grn_item_id']}',
            'store_id': stock['store_id'],
            'grn_item_id': stock['grn_item_id'],
            'material_name': stock['material_name'] ?? 'Unknown',
            'material_code': stock['material_code'] ?? '',
            'current_stock': stock['current_stock'] ?? 0,
            'unit': stock['unit'] ?? 'PCS',
            'last_updated': stock['last_updated'] ?? DateTime.now().toIso8601String(),
            'is_synced': 1,
            'created_at': stock['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at': stock['updated_at'] ?? DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      
      debugPrint('✅ Synced ${stockData.length} raw material stock records');
    } catch (e) {
      debugPrint('❌ Raw material stock sync error: $e');
    }
  }
}


// ============ MODELS ============

class Customer {
  final String id;
  final String orgId;
  final String? storeId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? address;
  final int totalOrders;
  final double totalSpent;
  final DateTime? lastOrderAt;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.orgId,
    this.storeId,
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.address,
    this.totalOrders = 0,
    this.totalSpent = 0,
    this.lastOrderAt,
    this.isSynced = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'store_id': storeId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_email': customerEmail,
      'address': address,
      'total_orders': totalOrders,
      'total_spent': totalSpent,
      'last_order_at': lastOrderAt?.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      orgId: map['org_id'] as String,
      storeId: map['store_id'] as String?,
      customerName: map['customer_name'] as String,
      customerPhone: map['customer_phone'] as String?,
      customerEmail: map['customer_email'] as String?,
      address: map['address'] as String?,
      totalOrders: (map['total_orders'] as int?) ?? 0,
      totalSpent: (map['total_spent'] as num?)?.toDouble() ?? 0,
      lastOrderAt: map['last_order_at'] != null ? DateTime.parse(map['last_order_at'] as String) : null,
      isSynced: (map['is_synced'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class HoldOrder {
  final String id;
  final String orgId;
  final String? storeId;
  final String userId;
  final String? userName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String orderType;
  final String? tableNumber;
  final String? tokenNumber;
  final double subTotal;
  final double discountAmount;
  final double discountPercentage;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double totalAmount;
  final String? remarks;
  final String? holdReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<HoldOrderItem> items;

  HoldOrder({
    required this.id,
    required this.orgId,
    this.storeId,
    required this.userId,
    this.userName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.orderType = 'dine_in',
    this.tableNumber,
    this.tokenNumber,
    required this.subTotal,
    this.discountAmount = 0,
    this.discountPercentage = 0,
    this.taxAmount = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    required this.totalAmount,
    this.remarks,
    this.holdReason,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'store_id': storeId,
      'user_id': userId,
      'user_name': userName,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'order_type': orderType,
      'table_number': tableNumber,
      'token_number': tokenNumber,
      'sub_total': subTotal,
      'discount_amount': discountAmount,
      'discount_percentage': discountPercentage,
      'tax_amount': taxAmount,
      'cgst_amount': cgstAmount,
      'sgst_amount': sgstAmount,
      'total_amount': totalAmount,
      'remarks': remarks,
      'hold_reason': holdReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory HoldOrder.fromMap(Map<String, dynamic> map, List<Map<String, dynamic>> itemMaps) {
    return HoldOrder(
      id: map['id'] as String,
      orgId: map['org_id'] as String,
      storeId: map['store_id'] as String?,
      userId: map['user_id'] as String,
      userName: map['user_name'] as String?,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      orderType: map['order_type'] as String? ?? 'dine_in',
      tableNumber: map['table_number'] as String?,
      tokenNumber: map['token_number'] as String?,
      subTotal: (map['sub_total'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      discountPercentage: (map['discount_percentage'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      cgstAmount: (map['cgst_amount'] as num?)?.toDouble() ?? 0,
      sgstAmount: (map['sgst_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      remarks: map['remarks'] as String?,
      holdReason: map['hold_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      items: itemMaps.map((m) => HoldOrderItem.fromMap(m)).toList(),
    );
  }
}

class HoldOrderItem {
  final String id;
  final String holdOrderId;
  final String itemId;
  final String? itemCode;
  final String itemName;
  final String? categoryName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double discountPercentage;
  final double discountAmount;
  final double taxPercentage;
  final double taxAmount;
  final double totalAmount;
  final String? imageUrl;
  final String? remarks;
  final DateTime createdAt;

  HoldOrderItem({
    required this.id,
    required this.holdOrderId,
    required this.itemId,
    this.itemCode,
    required this.itemName,
    this.categoryName,
    required this.quantity,
    this.unit = 'PCS',
    required this.unitPrice,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    this.taxPercentage = 0,
    this.taxAmount = 0,
    required this.totalAmount,
    this.imageUrl,
    this.remarks,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hold_order_id': holdOrderId,
      'item_id': itemId,
      'item_code': itemCode,
      'item_name': itemName,
      'category_name': categoryName,
      'quantity': quantity,
      'unit': unit,
      'unit_price': unitPrice,
      'discount_percentage': discountPercentage,
      'discount_amount': discountAmount,
      'tax_percentage': taxPercentage,
      'tax_amount': taxAmount,
      'total_amount': totalAmount,
      'image_url': imageUrl,
      'remarks': remarks,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory HoldOrderItem.fromMap(Map<String, dynamic> map) {
    return HoldOrderItem(
      id: map['id'] as String,
      holdOrderId: map['hold_order_id'] as String,
      itemId: map['item_id'] as String,
      itemCode: map['item_code'] as String?,
      itemName: map['item_name'] as String,
      categoryName: map['category_name'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
      unit: map['unit'] as String? ?? 'PCS',
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      discountPercentage: (map['discount_percentage'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      taxPercentage: (map['tax_percentage'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      imageUrl: map['image_url'] as String?,
      remarks: map['remarks'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}


// ============ LOCAL SALES ORDER MODEL ============

class LocalSalesOrder {
  final String id;
  final String storeId;
  final String? orderNumber;
  final String invoiceNo;
  final String orderType;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String orderDate;
  final String orderTime;
  final String orderTimestamp;
  final double subTotal;
  final double discountAmount;
  final double discountPercentage;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double totalAmount;
  final double roundOff;
  final double finalAmount;
  final String paymentMode;
  final String paymentStatus;
  final double amountPaid;
  final String orderStatus;
  final String? billedBy;
  final String? cashierName;
  final String? tableNumber;
  final String? tokenNumber;
  final String? remarks;
  final bool isSynced;
  final String? syncError;
  final DateTime? syncedAt;
  final DateTime createdAt;
  final List<LocalSalesOrderItem> items;

  LocalSalesOrder({
    required this.id,
    required this.storeId,
    this.orderNumber,
    required this.invoiceNo,
    this.orderType = 'dine_in',
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.orderDate,
    required this.orderTime,
    required this.orderTimestamp,
    required this.subTotal,
    this.discountAmount = 0,
    this.discountPercentage = 0,
    this.taxAmount = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    required this.totalAmount,
    this.roundOff = 0,
    required this.finalAmount,
    required this.paymentMode,
    this.paymentStatus = 'paid',
    required this.amountPaid,
    this.orderStatus = 'completed',
    this.billedBy,
    this.cashierName,
    this.tableNumber,
    this.tokenNumber,
    this.remarks,
    this.isSynced = false,
    this.syncError,
    this.syncedAt,
    required this.createdAt,
    required this.items,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'order_number': orderNumber,
      'invoice_no': invoiceNo,
      'order_type': orderType,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'order_date': orderDate,
      'order_time': orderTime,
      'order_timestamp': orderTimestamp,
      'sub_total': subTotal,
      'discount_amount': discountAmount,
      'discount_percentage': discountPercentage,
      'tax_amount': taxAmount,
      'cgst_amount': cgstAmount,
      'sgst_amount': sgstAmount,
      'total_amount': totalAmount,
      'round_off': roundOff,
      'final_amount': finalAmount,
      'payment_mode': paymentMode,
      'payment_status': paymentStatus,
      'amount_paid': amountPaid,
      'order_status': orderStatus,
      'billed_by': billedBy,
      'cashier_name': cashierName,
      'table_number': tableNumber,
      'token_number': tokenNumber,
      'remarks': remarks,
      'is_synced': isSynced ? 1 : 0,
      'sync_error': syncError,
      'synced_at': syncedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory LocalSalesOrder.fromMap(Map<String, dynamic> map, List<Map<String, dynamic>> itemMaps) {
    return LocalSalesOrder(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      orderNumber: map['order_number'] as String?,
      invoiceNo: map['invoice_no'] as String,
      orderType: map['order_type'] as String? ?? 'dine_in',
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      orderDate: map['order_date'] as String,
      orderTime: map['order_time'] as String,
      orderTimestamp: map['order_timestamp'] as String,
      subTotal: (map['sub_total'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      discountPercentage: (map['discount_percentage'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      cgstAmount: (map['cgst_amount'] as num?)?.toDouble() ?? 0,
      sgstAmount: (map['sgst_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      roundOff: (map['round_off'] as num?)?.toDouble() ?? 0,
      finalAmount: (map['final_amount'] as num?)?.toDouble() ?? 0,
      paymentMode: map['payment_mode'] as String? ?? 'cash',
      paymentStatus: map['payment_status'] as String? ?? 'paid',
      amountPaid: (map['amount_paid'] as num?)?.toDouble() ?? 0,
      orderStatus: map['order_status'] as String? ?? 'completed',
      billedBy: map['billed_by'] as String?,
      cashierName: map['cashier_name'] as String?,
      tableNumber: map['table_number'] as String?,
      tokenNumber: map['token_number'] as String?,
      remarks: map['remarks'] as String?,
      isSynced: (map['is_synced'] as int?) == 1,
      syncError: map['sync_error'] as String?,
      syncedAt: map['synced_at'] != null ? DateTime.parse(map['synced_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: itemMaps.map((m) => LocalSalesOrderItem.fromMap(m)).toList(),
    );
  }
}

class LocalSalesOrderItem {
  final String id;
  final String salesOrderId;
  final String productId;
  final String productName;
  final String? productCode;
  final double quantity;
  final String uom;
  final double unitPrice;
  final double discountPercentage;
  final double discountAmount;
  final double taxableAmount;
  final double taxPercentage;
  final double taxAmount;
  final double totalLineAmount;
  final int lineNumber;

  LocalSalesOrderItem({
    required this.id,
    required this.salesOrderId,
    required this.productId,
    required this.productName,
    this.productCode,
    required this.quantity,
    this.uom = 'PCS',
    required this.unitPrice,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    this.taxableAmount = 0,
    this.taxPercentage = 0,
    this.taxAmount = 0,
    required this.totalLineAmount,
    this.lineNumber = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sales_order_id': salesOrderId,
      'product_id': productId,
      'product_name': productName,
      'product_code': productCode,
      'quantity': quantity,
      'uom': uom,
      'unit_price': unitPrice,
      'discount_percentage': discountPercentage,
      'discount_amount': discountAmount,
      'taxable_amount': taxableAmount,
      'tax_percentage': taxPercentage,
      'tax_amount': taxAmount,
      'total_line_amount': totalLineAmount,
      'line_number': lineNumber,
    };
  }

  factory LocalSalesOrderItem.fromMap(Map<String, dynamic> map) {
    return LocalSalesOrderItem(
      id: map['id'] as String,
      salesOrderId: map['sales_order_id'] as String,
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      productCode: map['product_code'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
      uom: map['uom'] as String? ?? 'PCS',
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      discountPercentage: (map['discount_percentage'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      taxableAmount: (map['taxable_amount'] as num?)?.toDouble() ?? 0,
      taxPercentage: (map['tax_percentage'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      totalLineAmount: (map['total_line_amount'] as num?)?.toDouble() ?? 0,
      lineNumber: (map['line_number'] as int?) ?? 1,
    );
  }
}


// ============ LOCAL PRODUCT MODEL ============

class LocalProduct {
  final String id;
  final String orgId;
  final String? categoryId;
  final String itemCode;
  final String itemName;
  final String? shortName;
  final String? description;
  final String unit;
  final double sellingPrice;
  final double? mrp;
  final double taxRate;
  final String? imageUrl;
  final String? barcode;
  final bool isVeg;
  final bool isAvailable;
  final String? categoryName;
  final String? rawMaterialMapping; // JSON string
  final DateTime updatedAt;

  LocalProduct({
    required this.id,
    required this.orgId,
    this.categoryId,
    required this.itemCode,
    required this.itemName,
    this.shortName,
    this.description,
    this.unit = 'PCS',
    required this.sellingPrice,
    this.mrp,
    this.taxRate = 5,
    this.imageUrl,
    this.barcode,
    this.isVeg = true,
    this.isAvailable = true,
    this.categoryName,
    this.rawMaterialMapping,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'category_id': categoryId,
      'item_code': itemCode,
      'item_name': itemName,
      'short_name': shortName,
      'description': description,
      'unit': unit,
      'selling_price': sellingPrice,
      'mrp': mrp,
      'tax_rate': taxRate,
      'image_url': imageUrl,
      'barcode': barcode,
      'is_veg': isVeg ? 1 : 0,
      'is_available': isAvailable ? 1 : 0,
      'category_name': categoryName,
      'raw_material_mapping': rawMaterialMapping,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LocalProduct.fromMap(Map<String, dynamic> map) {
    return LocalProduct(
      id: map['id'] as String,
      orgId: map['org_id'] as String,
      categoryId: map['category_id'] as String?,
      itemCode: map['item_code'] as String? ?? '',
      itemName: map['item_name'] as String,
      shortName: map['short_name'] as String?,
      description: map['description'] as String?,
      unit: map['unit'] as String? ?? 'PCS',
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      mrp: (map['mrp'] as num?)?.toDouble(),
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 5,
      imageUrl: map['image_url'] as String?,
      barcode: map['barcode'] as String?,
      isVeg: (map['is_veg'] as int?) == 1,
      isAvailable: (map['is_available'] as int?) == 1,
      categoryName: map['category_name'] as String?,
      rawMaterialMapping: map['raw_material_mapping'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}


// ============ LOCAL CATEGORY MODEL ============

class LocalCategory {
  final String id;
  final String orgId;
  final String categoryCode;
  final String categoryName;
  final String? description;
  final int displayOrder;
  final String? imageUrl;
  final DateTime updatedAt;

  LocalCategory({
    required this.id,
    required this.orgId,
    required this.categoryCode,
    required this.categoryName,
    this.description,
    this.displayOrder = 0,
    this.imageUrl,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'category_code': categoryCode,
      'category_name': categoryName,
      'description': description,
      'display_order': displayOrder,
      'image_url': imageUrl,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LocalCategory.fromMap(Map<String, dynamic> map) {
    return LocalCategory(
      id: map['id'] as String,
      orgId: map['org_id'] as String,
      categoryCode: map['category_code'] as String? ?? '',
      categoryName: map['category_name'] as String,
      description: map['description'] as String?,
      displayOrder: (map['display_order'] as int?) ?? 0,
      imageUrl: map['image_url'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
