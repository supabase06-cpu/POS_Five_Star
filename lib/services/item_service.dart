import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item_model.dart';
import 'local_db_service.dart';
import 'debug_logger_service.dart';

class ItemService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDbService _localDb = LocalDbService();
  final DebugLoggerService _logger = DebugLoggerService();
  
  // Cache online status to avoid repeated checks
  bool? _isOnlineCache;
  DateTime? _lastOnlineCheck;

  /// Check if online (with caching for 5 seconds)
  Future<bool> _isOnline() async {
    // Use cached value if checked within last 5 seconds
    if (_isOnlineCache != null && _lastOnlineCheck != null) {
      if (DateTime.now().difference(_lastOnlineCheck!).inSeconds < 5) {
        return _isOnlineCache!;
      }
    }
    
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      _isOnlineCache = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      _isOnlineCache = false;
    }
    _lastOnlineCheck = DateTime.now();
    return _isOnlineCache!;
  }

  Future<List<ItemCategory>> getCategories(String orgId) async {
    // Check offline FIRST before making any request
    final online = await _isOnline();
    
    if (!online) {
      _logger.log('📴 Offline - loading categories from local DB');
      debugPrint('📴 Offline detected - loading categories from local DB');
      return await _getLocalCategories(orgId);
    }
    
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _supabase
          .from('item_categories')
          .select('*')
          .eq('org_id', orgId)
          .eq('is_active', true)
          .order('display_order');

      stopwatch.stop();
      _logger.logApi(
        title: 'GET item_categories',
        request: 'org_id=$orgId, is_active=true',
        response: 'Count: ${response.length}\n${jsonEncode(response.take(3).toList())}${response.length > 3 ? '...' : ''}',
        statusCode: 200,
        duration: stopwatch.elapsed,
      );

      debugPrint('📂 Categories: ${response.length}');
      return response.map<ItemCategory>((json) => ItemCategory.fromJson(json)).toList();
    } catch (e) {
      stopwatch.stop();
      _logger.logApi(
        title: 'GET item_categories',
        request: 'org_id=$orgId',
        error: e.toString(),
        statusCode: 500,
        duration: stopwatch.elapsed,
      );
      debugPrint('❌ Categories error: $e');
      debugPrint('📴 Falling back to local categories');
      return await _getLocalCategories(orgId);
    }
  }

  /// Get categories from local database
  Future<List<ItemCategory>> _getLocalCategories(String orgId) async {
    try {
      final localCategories = await _localDb.getLocalCategories(orgId);
      debugPrint('📂 Local Categories: ${localCategories.length}');
      
      return localCategories.map((c) => ItemCategory(
        id: c.id,
        orgId: c.orgId,
        categoryCode: c.categoryCode,
        categoryName: c.categoryName,
        description: c.description,
        displayOrder: c.displayOrder,
      )).toList();
    } catch (e) {
      debugPrint('❌ Local categories error: $e');
      return [];
    }
  }

  Future<List<Item>> getItems(String orgId, {String? categoryId, String? searchQuery}) async {
    // Check offline FIRST before making any request
    final online = await _isOnline();
    
    if (!online) {
      _logger.log('📴 Offline - loading items from local DB');
      debugPrint('📴 Offline detected - loading items from local DB');
      return await _getLocalItems(orgId, categoryId: categoryId, searchQuery: searchQuery);
    }
    
    final stopwatch = Stopwatch()..start();
    try {
      var query = _supabase
          .from('items')
          .select('*, category:item_categories(*), raw_material_mapping, total_pieces_limit')
          .eq('org_id', orgId)
          .eq('is_active', true)
          .eq('is_available', true);

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%,barcode.ilike.%$searchQuery%');
      }

      final response = await query.order('display_order').order('item_name');

      stopwatch.stop();
      _logger.logApi(
        title: 'GET items',
        request: 'org_id=$orgId, category_id=$categoryId, search=$searchQuery',
        response: 'Count: ${response.length}\n${jsonEncode(response.take(2).toList())}${response.length > 2 ? '...' : ''}',
        statusCode: 200,
        duration: stopwatch.elapsed,
      );

      debugPrint('📦 Items: ${response.length}');
      final items = response.map<Item>((json) => Item.fromJson(json)).toList();
      
      // Debug: Check if raw material mapping is loaded
      for (final item in items) {
        if (item.rawMaterialMapping != null && item.rawMaterialMapping!.isNotEmpty) {
          debugPrint('✅ Item ${item.itemName} has ${item.rawMaterialMapping!.length} raw material mappings');
        }
      }
      
      return items;
    } catch (e) {
      stopwatch.stop();
      _logger.logApi(
        title: 'GET items',
        request: 'org_id=$orgId, category_id=$categoryId',
        error: e.toString(),
        statusCode: 500,
        duration: stopwatch.elapsed,
      );
      debugPrint('❌ Items error: $e');
      debugPrint('📴 Falling back to local items');
      return await _getLocalItems(orgId, categoryId: categoryId, searchQuery: searchQuery);
    }
  }

  /// Get items from local database when offline
  Future<List<Item>> _getLocalItems(String orgId, {String? categoryId, String? searchQuery}) async {
    try {
      final localProducts = await _localDb.getLocalProducts(orgId, categoryId: categoryId, searchQuery: searchQuery);
      debugPrint('📦 Local Items: ${localProducts.length}');
      
      return localProducts.map((p) {
        // Parse raw material mapping from JSON string
        List<RawMaterialMapping>? rawMaterialMapping;
        if (p.rawMaterialMapping != null && p.rawMaterialMapping!.isNotEmpty) {
          try {
            final mappingJson = jsonDecode(p.rawMaterialMapping!) as List;
            rawMaterialMapping = mappingJson.map((json) => RawMaterialMapping.fromJson(json)).toList();
            debugPrint('✅ Local Item ${p.itemName}: ${rawMaterialMapping.length} raw material mappings loaded');
          } catch (e) {
            debugPrint('❌ Error parsing raw material mapping for ${p.itemName}: $e');
          }
        } else {
          debugPrint('⚠️ Local Item ${p.itemName}: No raw material mapping');
        }
        
        return Item(
          id: p.id,
          orgId: p.orgId,
          categoryId: p.categoryId,
          itemCode: p.itemCode,
          itemName: p.itemName,
          shortName: p.shortName,
          description: p.description,
          unit: p.unit,
          sellingPrice: p.sellingPrice,
          mrp: p.mrp,
          taxRate: p.taxRate,
          imageUrl: p.imageUrl,
          barcode: p.barcode,
          isVeg: p.isVeg,
          isAvailable: p.isAvailable,
          rawMaterialMapping: rawMaterialMapping, // Add the parsed mapping
          category: p.categoryId != null ? ItemCategory(
            id: p.categoryId!,
            orgId: p.orgId,
            categoryCode: '',
            categoryName: p.categoryName ?? 'Unknown',
          ) : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Local items error: $e');
      return [];
    }
  }

  Future<Map<String, int>> getStockLevels(String storeId, List<String> itemIds) async {
    // Check offline FIRST
    final online = await _isOnline();
    
    if (!online) {
      // Return unlimited stock in offline mode
      Map<String, int> defaultStock = {};
      for (String itemId in itemIds) {
        defaultStock[itemId] = 999;
      }
      return defaultStock;
    }
    
    try {
      final response = await _supabase
          .from('stock_levels')
          .select('product_id, current_qty')
          .eq('store_id', storeId)
          .inFilter('product_id', itemIds);

      Map<String, int> stockMap = {};
      for (var stock in response) {
        stockMap[stock['product_id']] = (stock['current_qty'] ?? 0).toInt();
      }
      return stockMap;
    } catch (e) {
      // Return default stock if error
      Map<String, int> defaultStock = {};
      for (String itemId in itemIds) {
        defaultStock[itemId] = 999;
      }
      return defaultStock;
    }
  }

  Future<List<Item>> searchItems(String orgId, String query) async {
    if (query.isEmpty) return [];
    return getItems(orgId, searchQuery: query);
  }
}
