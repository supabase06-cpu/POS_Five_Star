import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_service.dart';
import 'image_cache_service.dart';
import 'debug_logger_service.dart';

class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDbService _localDb = LocalDbService();
  final ImageCacheService _imageCache = ImageCacheService();
  final DebugLoggerService _logger = DebugLoggerService();
  
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _lastOnlineStatus = true;
  
  // Sync status
  OfflineSyncStatus _status = OfflineSyncStatus();
  OfflineSyncStatus get status => _status;
  
  // Callbacks for UI updates
  Function(OfflineSyncStatus)? onStatusChanged;
  Function()? onConnectivityRestored;

  /// Check if online
  Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      
      // Log status change
      if (online != _lastOnlineStatus) {
        if (online) {
          debugPrint('🌐 Online detected - connected to internet');
          // Trigger immediate sync when connectivity is restored
          if (onConnectivityRestored != null) {
            onConnectivityRestored!();
          }
        } else {
          debugPrint('📴 Offline detected - no internet connection');
        }
        _lastOnlineStatus = online;
      }
      
      return online;
    } catch (_) {
      if (_lastOnlineStatus) {
        debugPrint('📴 Offline detected - no internet connection');
        _lastOnlineStatus = false;
      }
      return false;
    }
  }

  /// Initialize offline data on app start
  Future<OfflineSyncStatus> initializeOfflineData(String orgId, String storeId) async {
    _status = OfflineSyncStatus(isLoading: true);
    _notifyStatusChanged();

    try {
      final online = await isOnline();
      
      if (online) {
        // Sync from cloud to local
        await _syncCategoriesFromCloud(orgId);
        
        // Check if we need to force re-sync products (for raw material mapping)
        await _checkAndResyncProducts(orgId);
        
        await _syncCustomersFromCloud(orgId, storeId);
        await _syncRawMaterialStockFromCloud(storeId);
        await _syncLastInvoiceNumber(storeId);
        
        // Get final counts after sync
        final productsCount = await _localDb.getLocalProductsCount();
        final categoriesCount = await _localDb.getLocalCategoriesCount(orgId);
        final customersCount = await _localDb.getLocalCustomersCount(orgId);
        final productsWithMappingCount = await _localDb.getProductsWithMappingCount(orgId);
        final cacheStats = await _imageCache.getCacheStats();
        
        _status = OfflineSyncStatus(
          isReady: true,
          isOnline: true,
          productsCount: productsCount,
          categoriesCount: categoriesCount,
          customersCount: customersCount,
          cachedImagesCount: cacheStats['cached_images'] ?? 0,
          productsWithMappingCount: productsWithMappingCount,
          lastInvoiceNumber: _status.lastInvoiceNumber,
          lastSyncTime: DateTime.now(),
        );
      } else {
        // Load counts from local DB
        final productsCount = await _localDb.getLocalProductsCount();
        final categoriesCount = await _localDb.getLocalCategoriesCount(orgId);
        final customersCount = await _localDb.getLocalCustomersCount(orgId);
        final productsWithMappingCount = await _localDb.getProductsWithMappingCount(orgId);
        final lastInvoice = await _getLastInvoiceFromPrefs();
        final cacheStats = await _imageCache.getCacheStats();
        
        _status = OfflineSyncStatus(
          isReady: productsCount > 0,
          isOnline: false,
          productsCount: productsCount,
          categoriesCount: categoriesCount,
          customersCount: customersCount,
          cachedImagesCount: cacheStats['cached_images'] ?? 0,
          productsWithMappingCount: productsWithMappingCount,
          lastInvoiceNumber: lastInvoice,
          lastSyncTime: await _getLastSyncTime(),
        );
      }
      
      // Save last sync time
      await _saveLastSyncTime();
      
    } catch (e) {
      debugPrint('❌ Offline init error: $e');
      _status = OfflineSyncStatus(
        isReady: false,
        isOnline: false,
        error: e.toString(),
      );
    }

    _notifyStatusChanged();
    final msg = '📦 Offline ready: ${_status.productsCount} products, ${_status.categoriesCount} categories, ${_status.customersCount} customers';
    debugPrint(msg);
    _logger.log(msg);
    return _status;
  }

  /// Sync categories from cloud (delta sync based on updated_at)
  Future<void> _syncCategoriesFromCloud(String orgId) async {
    try {
      final localCount = await _localDb.getLocalCategoriesCount(orgId);
      final lastSync = await _getLastSyncTime();
      
      debugPrint('🔍 Categories: local=$localCount, lastSync=${lastSync != null}');
      _logger.log('🔍 Categories: local=$localCount, lastSync=${lastSync != null}');
      
      List<dynamic> categories;
      
      if (localCount == 0) {
        // Full sync - empty local DB
        categories = await _supabase
            .from('item_categories')
            .select()
            .eq('org_id', orgId)
            .eq('is_active', true)
            .order('display_order');
        
        debugPrint('📥 Full sync: ${categories.length} categories (local was empty)');
        _logger.log('📥 Full sync: ${categories.length} categories (local was empty)');
      } else if (lastSync != null) {
        // Delta sync - only get updated categories
        categories = await _supabase
            .from('item_categories')
            .select()
            .eq('org_id', orgId)
            .eq('is_active', true)
            .gt('updated_at', lastSync.toIso8601String())
            .order('updated_at');
        
        if (categories.isEmpty) {
          debugPrint('✅ Categories up to date ($localCount in local DB)');
          _logger.log('✅ Categories up to date ($localCount in local DB)');
          _status.categoriesCount = localCount;
          return;
        }
        debugPrint('🔄 Delta sync: ${categories.length} updated categories');
        _logger.log('🔄 Delta sync: ${categories.length} updated categories');
      } else {
        // Full sync - first time
        categories = await _supabase
            .from('item_categories')
            .select()
            .eq('org_id', orgId)
            .eq('is_active', true)
            .order('display_order');
        
        debugPrint('📥 Full sync: ${categories.length} categories (first time)');
        _logger.log('📥 Full sync: ${categories.length} categories (first time)');
      }

      for (var cat in categories) {
        await _localDb.saveLocalCategory(LocalCategory(
          id: cat['id'],
          orgId: cat['org_id'],
          categoryCode: cat['category_code'] ?? '',
          categoryName: cat['category_name'],
          description: cat['description'],
          displayOrder: cat['display_order'] ?? 0,
          imageUrl: cat['image_url'],
          updatedAt: DateTime.parse(cat['updated_at'] ?? DateTime.now().toIso8601String()),
        ));
      }

      // Update count from local DB after sync
      _status.categoriesCount = await _localDb.getLocalCategoriesCount(orgId);
    } catch (e) {
      debugPrint('❌ Categories sync error: $e');
    }
  }

  /// Check if products need re-sync for raw material mapping
  Future<void> _checkAndResyncProducts(String orgId) async {
    try {
      // First ensure the raw_material_mapping column exists
      await _localDb.ensureRawMaterialTablesExist();
      
      // Check if any local products have raw material mapping
      final db = await _localDb.database;
      
      // Check if column exists before querying
      final tableInfo = await db.rawQuery("PRAGMA table_info(local_products)");
      final hasColumn = tableInfo.any((column) => column['name'] == 'raw_material_mapping');
      
      if (!hasColumn) {
        debugPrint('⚠️ raw_material_mapping column missing - forcing re-sync...');
        await forceSyncProductsFromCloud(orgId);
        return;
      }
      
      final result = await db.rawQuery(
        "SELECT COUNT(*) as total, COUNT(CASE WHEN raw_material_mapping IS NOT NULL AND raw_material_mapping != '' THEN 1 END) as with_mapping FROM local_products WHERE org_id = ?",
        [orgId]
      );
      
      final total = result.first['total'] as int? ?? 0;
      final withMapping = result.first['with_mapping'] as int? ?? 0;
      
      debugPrint('🔍 Local products: $total total, $withMapping with raw material mapping');
      
      if (total > 0 && withMapping == 0) {
        // We have products but none have raw material mapping - force re-sync
        debugPrint('🔄 No products have raw material mapping - forcing re-sync...');
        await forceSyncProductsFromCloud(orgId);
      } else {
        // Normal sync
        await _syncProductsFromCloud(orgId);
      }
    } catch (e) {
      debugPrint('❌ Error checking product mapping status: $e');
      // Fallback to force sync to ensure we get the latest data
      await forceSyncProductsFromCloud(orgId);
    }
  }

  /// Force sync products from cloud (ignores lastSync time)
  Future<void> forceSyncProductsFromCloud(String orgId) async {
    try {
      debugPrint('🔄 Force syncing products from cloud...');
      
      // Get all products with raw material mapping
      final products = await _supabase
          .from('items')
          .select('*, item_categories(category_name), raw_material_mapping')
          .eq('org_id', orgId)
          .eq('is_active', true)
          .order('item_name');
      
      debugPrint('📥 Force sync: ${products.length} products from cloud');
      
      // Save to local DB and collect images for caching
      List<Map<String, String>> imagesToCache = [];
      
      for (var product in products) {
        await _localDb.saveLocalProduct(LocalProduct(
          id: product['id'],
          orgId: product['org_id'],
          categoryId: product['category_id'],
          itemCode: product['item_code'] ?? '',
          itemName: product['item_name'],
          shortName: product['short_name'],
          description: product['description'],
          unit: product['unit'] ?? 'PCS',
          sellingPrice: (product['selling_price'] as num?)?.toDouble() ?? 0,
          mrp: (product['mrp'] as num?)?.toDouble(),
          taxRate: (product['tax_rate'] as num?)?.toDouble() ?? 5,
          imageUrl: product['image_url'],
          barcode: product['barcode'],
          isVeg: product['is_veg'] ?? true,
          isAvailable: product['is_available'] ?? true,
          categoryName: product['item_categories']?['category_name'],
          rawMaterialMapping: product['raw_material_mapping'] != null 
              ? jsonEncode(product['raw_material_mapping']) 
              : null,
          updatedAt: DateTime.parse(product['updated_at']),
        ));
        
        // Debug log for raw material mapping
        if (product['raw_material_mapping'] != null) {
          final mappingCount = (product['raw_material_mapping'] as List).length;
          debugPrint('📋 Force sync - Product ${product['item_name']}: $mappingCount raw materials mapped');
        } else {
          debugPrint('⚠️ Force sync - Product ${product['item_name']}: No raw material mapping');
        }
        
        // Collect image for caching
        if (product['image_url'] != null && product['image_url'].toString().isNotEmpty) {
          imagesToCache.add({
            'id': product['id'],
            'image_url': product['image_url'],
          });
        }
      }

      // Cache images in background
      if (imagesToCache.isNotEmpty) {
        debugPrint('📷 Caching ${imagesToCache.length} product images...');
        _imageCache.cacheProductImages(imagesToCache);
      }

      // Update count from local DB after sync
      _status.productsCount = await _localDb.getLocalProductsCount();
      _status.productsWithMappingCount = await _localDb.getProductsWithMappingCount(orgId);
      
      debugPrint('✅ Force sync completed: ${products.length} products with raw material mappings');
    } catch (e) {
      debugPrint('❌ Force sync products error: $e');
    }
  }

  /// Sync products from cloud (delta sync based on updated_at)
  Future<void> _syncProductsFromCloud(String orgId) async {
    try {
      // Always check local count first
      final localCount = await _localDb.getLocalProductsCount();
      final lastSync = await _getLastSyncTime();
      
      debugPrint('🔍 Products: local=$localCount, lastSync=${lastSync != null}');
      _logger.log('🔍 Products: local=$localCount, lastSync=${lastSync != null}');
      
      List<dynamic> products;
      // Force full sync if local DB is empty
      if (localCount == 0) {
        // Full sync - empty local DB
        products = await _supabase
            .from('items')
            .select('*, item_categories(category_name), raw_material_mapping')
            .eq('org_id', orgId)
            .eq('is_active', true)
            .order('item_name');
        
        debugPrint('📥 Full sync: ${products.length} products (local was empty)');
        _logger.log('📥 Full sync: ${products.length} products (local was empty)');
      } else if (lastSync != null) {
        // Delta sync - only get updated products
        products = await _supabase
            .from('items')
            .select('*, item_categories(category_name), raw_material_mapping')
            .eq('org_id', orgId)
            .eq('is_active', true)
            .gt('updated_at', lastSync.toIso8601String())
            .order('updated_at');
        
        if (products.isEmpty) {
          debugPrint('✅ Products up to date ($localCount in local DB)');
          _logger.log('✅ Products up to date ($localCount in local DB)');
          return;
        }
        debugPrint('🔄 Delta sync: ${products.length} updated products');
        _logger.log('🔄 Delta sync: ${products.length} updated products');
      } else {
        // Full sync - first time
        products = await _supabase
            .from('items')
            .select('*, item_categories(category_name), raw_material_mapping')
            .eq('org_id', orgId)
            .eq('is_active', true)
            .order('item_name');
        
        debugPrint('📥 Full sync: ${products.length} products (first time)');
        _logger.log('📥 Full sync: ${products.length} products (first time)');
      }

      // Save to local DB and collect images for caching
      List<Map<String, String>> imagesToCache = [];
      
      for (var product in products) {
        await _localDb.saveLocalProduct(LocalProduct(
          id: product['id'],
          orgId: product['org_id'],
          categoryId: product['category_id'],
          itemCode: product['item_code'] ?? '',
          itemName: product['item_name'],
          shortName: product['short_name'],
          description: product['description'],
          unit: product['unit'] ?? 'PCS',
          sellingPrice: (product['selling_price'] as num?)?.toDouble() ?? 0,
          mrp: (product['mrp'] as num?)?.toDouble(),
          taxRate: (product['tax_rate'] as num?)?.toDouble() ?? 5,
          imageUrl: product['image_url'],
          barcode: product['barcode'],
          isVeg: product['is_veg'] ?? true,
          isAvailable: product['is_available'] ?? true,
          categoryName: product['item_categories']?['category_name'],
          rawMaterialMapping: product['raw_material_mapping'] != null 
              ? jsonEncode(product['raw_material_mapping']) 
              : null,
          updatedAt: DateTime.parse(product['updated_at']),
        ));
        
        // Debug log for raw material mapping
        if (product['raw_material_mapping'] != null) {
          final mappingCount = (product['raw_material_mapping'] as List).length;
          debugPrint('📋 Product ${product['item_name']}: $mappingCount raw materials mapped');
        }
        
        // Collect image for caching
        if (product['image_url'] != null && product['image_url'].toString().isNotEmpty) {
          imagesToCache.add({
            'id': product['id'],
            'image_url': product['image_url'],
          });
        }
      }

      debugPrint('✅ Saved ${products.length} products to local DB');
      _logger.log('✅ Saved ${products.length} products to local DB');
      
      // Cache images in background
      if (imagesToCache.isNotEmpty) {
        _cacheImagesInBackground(imagesToCache);
      }
    } catch (e) {
      debugPrint('❌ Products sync error: $e');
    }
  }

  /// Cache images in background
  Future<void> _cacheImagesInBackground(List<Map<String, dynamic>> images) async {
    try {
      await _imageCache.cacheProductImages(images);
      final stats = await _imageCache.getCacheStats();
      _status.cachedImagesCount = stats['cached_images'] ?? 0;
      _notifyStatusChanged(); // Notify UI of the updated cache count
      _logger.log('✅ Cached ${images.length} product images');
    } catch (e) {
      debugPrint('❌ Image caching error: $e');
      _logger.log('❌ Image caching error: $e');
    }
  }

  /// Sync customers from cloud (delta sync)
  Future<void> _syncCustomersFromCloud(String orgId, String storeId) async {
    try {
      // Always check local count first
      final localCount = await _localDb.getLocalCustomersCount(orgId);
      final lastSync = await _getLastSyncTime();
      
      debugPrint('🔍 Customers: local=$localCount, lastSync=${lastSync != null}');
      _logger.log('🔍 Customers: local=$localCount, lastSync=${lastSync != null}');
      
      // Since you enabled real-time, let's do a full sync to handle deletions
      final customers = await _supabase
          .from('customers')
          .select()
          .eq('org_id', orgId)
          .order('customer_name');
      
      debugPrint('📥 Full sync: ${customers.length} customers from cloud');
      _logger.log('📥 Full sync: ${customers.length} customers from cloud');

      // Get current customer IDs from cloud
      final cloudCustomerIds = customers.map((c) => c['id'] as String).toSet();
      
      // Get local customer IDs
      final localCustomers = await _localDb.getCustomers(orgId);
      final localCustomerIds = localCustomers.map((c) => c.id).toSet();
      
      // Delete customers that are no longer in cloud
      final customersToDelete = localCustomerIds.difference(cloudCustomerIds);
      for (final customerId in customersToDelete) {
        await _localDb.deleteCustomer(customerId);
        debugPrint('🗑️ Deleted customer: $customerId');
      }

      // Save/update customers from cloud
      for (var customer in customers) {
        // Debug: Check for data integrity issues
        final customerName = customer['customer_name'] ?? '';
        final customerPhone = customer['customer_phone'];
        
        // Validate that name doesn't look like a phone number
        if (customerName.isNotEmpty && RegExp(r'^\+?[\d\s\-\(\)]+$').hasMatch(customerName)) {
          debugPrint('⚠️ WARNING: Customer name looks like phone number: "$customerName"');
          debugPrint('⚠️ Customer phone: "$customerPhone"');
          debugPrint('⚠️ Customer ID: ${customer['id']}');
        }
        
        // Validate that phone doesn't look like a name (contains letters)
        if (customerPhone != null && RegExp(r'[a-zA-Z]').hasMatch(customerPhone)) {
          debugPrint('⚠️ WARNING: Customer phone looks like name: "$customerPhone"');
          debugPrint('⚠️ Customer name: "$customerName"');
          debugPrint('⚠️ Customer ID: ${customer['id']}');
        }
        
        final localCustomer = Customer(
          id: customer['id'],
          orgId: customer['org_id'],
          storeId: customer['store_id'],
          customerName: customerName,
          customerPhone: customerPhone,
          customerEmail: customer['customer_email'],
          address: customer['address'],
          totalOrders: customer['total_orders'] ?? 0,
          totalSpent: (customer['total_spent'] as num?)?.toDouble() ?? 0,
          lastOrderAt: customer['last_order_at'] != null 
              ? DateTime.parse(customer['last_order_at']) 
              : null,
          isSynced: true,
          createdAt: DateTime.parse(customer['created_at']),
          updatedAt: DateTime.parse(customer['updated_at']),
        );
        await _localDb.saveOrUpdateCustomer(localCustomer);
      }

      debugPrint('✅ Synced ${customers.length} customers, deleted ${customersToDelete.length} customers');
      _logger.log('✅ Synced ${customers.length} customers, deleted ${customersToDelete.length} customers');
    } catch (e) {
      debugPrint('❌ Customers sync error: $e');
    }
  }

  /// Get last invoice number from cloud
  Future<void> _syncLastInvoiceNumber(String storeId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final result = await _supabase
          .from('sales_orders')
          .select('invoice_no')
          .eq('store_id', storeId)
          .eq('order_date', today)
          .order('order_timestamp', ascending: false)
          .limit(1);

      if (result.isNotEmpty) {
        _status.lastInvoiceNumber = result[0]['invoice_no'];
        await _saveLastInvoice(_status.lastInvoiceNumber!);
      }
    } catch (e) {
      debugPrint('❌ Invoice sync error: $e');
    }
  }

  /// Start background sync timer
  void startBackgroundSync(String orgId, String storeId) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!_isSyncing) {
        await _backgroundSync(orgId, storeId);
      }
    });
  }

  /// Stop background sync
  void stopBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Background sync - check for changes
  Future<void> _backgroundSync(String orgId, String storeId) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final online = await isOnline();
      if (!online) {
        _status.isOnline = false;
        _notifyStatusChanged();
        _isSyncing = false;
        return;
      }

      _status.isOnline = true;
      
      // Sync changes from cloud
      await _syncProductsFromCloud(orgId);
      await _syncCustomersFromCloud(orgId, storeId);
      
      // Update counts after sync
      _status.productsCount = await _localDb.getLocalProductsCount();
      _status.productsWithMappingCount = await _localDb.getProductsWithMappingCount(orgId);
      _status.customersCount = await _localDb.getLocalCustomersCount(orgId);
      
      // Save sync time
      await _saveLastSyncTime();
      _status.lastSyncTime = DateTime.now();
      
      _notifyStatusChanged();
    } catch (e) {
      debugPrint('❌ Background sync error: $e');
    }

    _isSyncing = false;
  }

  /// Force sync now
  Future<OfflineSyncStatus> syncNow(String orgId, String storeId) async {
    _status.isLoading = true;
    _notifyStatusChanged();
    
    await _backgroundSync(orgId, storeId);
    
    _status.isLoading = false;
    _notifyStatusChanged();
    
    return _status;
  }

  /// Force database recreation (for development/testing)
  Future<void> recreateDatabase() async {
    try {
      debugPrint('🔄 Recreating database...');
      await _localDb.recreateDatabase();
      debugPrint('✅ Database recreated successfully');
    } catch (e) {
      debugPrint('❌ Error recreating database: $e');
    }
  }

  /// Force re-sync products with raw material mapping
  Future<void> forceResyncProducts(String orgId) async {
    final online = await isOnline();
    if (!online) {
      debugPrint('📴 Cannot force resync - offline');
      return;
    }
    
    debugPrint('🔄 Force re-syncing products with raw material mapping...');
    await forceSyncProductsFromCloud(orgId);
    debugPrint('✅ Force re-sync completed');
  }

  /// Sync raw material stock from cloud
  Future<void> _syncRawMaterialStockFromCloud(String storeId) async {
    try {
      debugPrint('🔄 Syncing raw material stock for store: $storeId');
      
      // Ensure tables exist before syncing
      await _localDb.ensureRawMaterialTablesExist();
      
      await _localDb.syncRawMaterialStockFromCloud(storeId);
      debugPrint('✅ Raw material stock sync completed');
    } catch (e) {
      debugPrint('❌ Raw material stock sync error: $e');
    }
  }

  // ============ PREFERENCES HELPERS ============

  Future<DateTime?> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString('last_offline_sync');
    return timeStr != null ? DateTime.parse(timeStr) : null;
  }

  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_offline_sync', DateTime.now().toIso8601String());
  }

  Future<String?> _getLastInvoiceFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_invoice_number');
  }

  Future<void> _saveLastInvoice(String invoice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_invoice_number', invoice);
  }

  void _notifyStatusChanged() {
    onStatusChanged?.call(_status);
  }
}

/// Offline sync status model
class OfflineSyncStatus {
  bool isReady;
  bool isOnline;
  bool isLoading;
  int productsCount;
  int categoriesCount;
  int customersCount;
  int cachedImagesCount;
  int productsWithMappingCount; // New: Count of products with raw material mapping
  String? lastInvoiceNumber;
  DateTime? lastSyncTime;
  String? error;

  OfflineSyncStatus({
    this.isReady = false,
    this.isOnline = false,
    this.isLoading = false,
    this.productsCount = 0,
    this.categoriesCount = 0,
    this.customersCount = 0,
    this.cachedImagesCount = 0,
    this.productsWithMappingCount = 0, // New: Default to 0
    this.lastInvoiceNumber,
    this.lastSyncTime,
    this.error,
  });

  String get statusText {
    if (isLoading) return 'Syncing...';
    if (!isReady) return 'Not Ready';
    if (isOnline) return 'Ready for Offline';
    return 'Offline Mode';
  }

  String get summaryText {
    final mappingText = productsWithMappingCount > 0 
        ? ' ($productsWithMappingCount with raw material mapping)'
        : ' (no raw material mapping)';
    return '$productsCount Products$mappingText • $categoriesCount Categories • $customersCount Customers';
  }

  String get lastSyncText {
    if (lastSyncTime == null) return 'Never synced';
    final diff = DateTime.now().difference(lastSyncTime!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
