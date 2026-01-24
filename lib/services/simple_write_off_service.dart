import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/simple_write_off_model.dart';
import '../models/inward_model.dart';
import 'unit_conversion_service.dart';

class SimpleWriteOffService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get products available for write off (from grn_stock_levels)
  Future<List<InwardProduct>> getProductsForWriteOff(String orgId, {String? searchQuery}) async {
    try {
      debugPrint('🔍 Fetching products for write off from raw_material_stock_status...');
      debugPrint('🏪 Store ID: $orgId');
      debugPrint('🔎 Search Query: ${searchQuery ?? "none"}');
      
      // Get products with current stock from raw_material_stock_status
      var query = _supabase
          .from('raw_material_stock_status')
          .select('''
            *,
            grn_master_items!inner(
              id,
              item_code,
              item_name,
              short_name,
              uom,
              categories(category_name)
            )
          ''')
          .eq('store_id', orgId)
          .eq('grn_master_items.is_active', true)
          .gt('current_stock', 0); // Only items with available stock

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('grn_master_items.item_name.ilike.%$searchQuery%,grn_master_items.item_code.ilike.%$searchQuery%');
      }

      final response = await query.limit(50);
      
      debugPrint('📦 Raw response: ${response.length} records');
      
      final products = response.map<InwardProduct>((item) {
        final grnItem = item['grn_master_items'];
        final availableQty = (item['current_stock'] as num?)?.toDouble() ?? 0;
        
        debugPrint('📋 Product: ${grnItem['item_name']} - Stock: $availableQty ${grnItem['uom']}');
        
        return InwardProduct(
          id: grnItem['id'],
          orgId: orgId,
          productCode: grnItem['item_code'],
          productName: grnItem['item_name'],
          shortName: grnItem['short_name'],
          uom: grnItem['uom'] ?? 'PCS',
          categoryName: grnItem['categories']?['category_name'],
          currentStock: availableQty,
          costPrice: (item['unit_cost'] as num?)?.toDouble() ?? 0,
        );
      }).toList();

      // Sort by product name in Dart
      products.sort((a, b) => a.productName.compareTo(b.productName));

      debugPrint('✅ Products available for write off: ${products.length} (from raw_material_stock_status)');
      return products;
    } catch (e) {
      debugPrint('❌ Get products for write off error: $e');
      debugPrint('🔄 Falling back to grn_master_items...');
      // Fallback to grn_master_items if the stock query fails
      return _getFallbackProducts(orgId, searchQuery);
    }
  }

  /// Fallback method to get products from grn_master_items
  Future<List<InwardProduct>> _getFallbackProducts(String orgId, String? searchQuery) async {
    try {
      var query = _supabase
          .from('grn_master_items')
          .select('*, categories(category_name)')
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%');
      }

      final response = await query.order('item_name').limit(50);
      
      final products = response.map<InwardProduct>((p) {
        // Add org_id to the map for fromGrnItem method
        p['org_id'] = orgId;
        return InwardProduct.fromGrnItem(p);
      }).toList();

      debugPrint('🔍 Fallback products loaded: ${products.length}');
      return products;
    } catch (e) {
      debugPrint('❌ Fallback products error: $e');
      return [];
    }
  }

  /// Generate write off number
  Future<String> generateWriteOffNumber(String storeId) async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

      final result = await _supabase
          .from('write_off_headers')
          .select('id')
          .eq('store_id', storeId)
          .gte('write_off_date', today.toIso8601String().split('T')[0])
          .count();

      final count = (result.count ?? 0) + 1;
      final writeOffNumber = 'WO-$dateStr-${count.toString().padLeft(4, '0')}';
      debugPrint('📝 Generated Write Off Number: $writeOffNumber');
      return writeOffNumber;
    } catch (e) {
      debugPrint('❌ Generate write off number error: $e');
      final timestamp = DateTime.now().millisecondsSinceEpoch % 10000;
      return 'WO-${DateTime.now().toIso8601String().split('T')[0].replaceAll('-', '')}-$timestamp';
    }
  }

  /// Create simple write off
  Future<String?> createWriteOff({
    required String storeId,
    required String writeOffNumber,
    required DateTime writeOffDate,
    required String writeOffReason,
    required String requestedBy,
    String? remarks,
    required List<SimpleWriteOffCartItem> items,
  }) async {
    try {
      debugPrint('📝 Creating simple write off: $writeOffNumber');

      // Create header
      final headerResponse = await _supabase
          .from('write_off_headers')
          .insert({
            'store_id': storeId,
            'write_off_number': writeOffNumber,
            'write_off_date': writeOffDate.toIso8601String().split('T')[0],
            'write_off_reason': writeOffReason,
            'write_off_status': 'pending',
            'requested_by': requestedBy,
            'remarks': remarks,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final writeOffId = headerResponse['id'];

      // Create items
      final itemsData = items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        
        return {
          'write_off_id': writeOffId,
          'product_id': item.productId,
          'quantity': item.quantity,
          'unit_cost': item.unitCost,
          'total_amount': item.quantity * item.unitCost,
          'item_condition': item.writeOffReason,
          'remarks': item.remarks,
          'created_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await _supabase.from('write_off_items').insert(itemsData);

      // Reduce stock levels for each item with unit conversion
      for (final item in items) {
        await _reduceStockForWriteOff(
          storeId: storeId,
          productId: item.productId,
          productName: item.productName,
          writeOffQuantity: item.quantity,
          writeOffUnit: item.uom,
          writeOffId: writeOffId,
          writeOffReason: item.writeOffReason,
          userId: requestedBy,
        );
      }

      debugPrint('✅ Simple write off created: $writeOffNumber');
      return writeOffId;
    } catch (e) {
      debugPrint('❌ Create simple write off error: $e');
      return null;
    }
  }

  /// Get write off history
  Future<List<SimpleWriteOffHeader>> getWriteOffHistory({
    required String storeId,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int limit = 100,
    String? searchQuery,
    String? status,
  }) async {
    try {
      final from = (page - 1) * limit;
      final to = from + limit - 1;

      var query = _supabase
          .from('write_off_headers')
          .select('''
            *,
            requested_user:app_users!requested_by(full_name)
          ''')
          .eq('store_id', storeId);

      // Add date filtering
      if (fromDate != null) {
        query = query.gte('write_off_date', fromDate.toIso8601String().split('T')[0]);
      }
      
      if (toDate != null) {
        query = query.lte('write_off_date', toDate.toIso8601String().split('T')[0]);
      }

      if (status != null && status.isNotEmpty) {
        query = query.eq('write_off_status', status);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('write_off_number.ilike.%$searchQuery%,write_off_reason.ilike.%$searchQuery%');
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(from, to);

      final writeOffs = (response as List)
          .map<SimpleWriteOffHeader>((data) => SimpleWriteOffHeader.fromMap(data))
          .toList();

      debugPrint('📋 Simple write offs loaded: ${writeOffs.length} (from: ${fromDate?.toIso8601String().split('T')[0] ?? 'any'}, to: ${toDate?.toIso8601String().split('T')[0] ?? 'any'})');
      return writeOffs;
    } catch (e) {
      debugPrint('❌ Get simple write off history error: $e');
      return [];
    }
  }

  /// Get write off items for a specific write-off
  Future<List<SimpleWriteOffItem>> getWriteOffItems(String writeOffId) async {
    try {
      // First get the write-off items
      final itemsResponse = await _supabase
          .from('write_off_items')
          .select('*')
          .eq('write_off_id', writeOffId)
          .order('created_at');

      final items = <SimpleWriteOffItem>[];
      
      for (final itemData in itemsResponse) {
        // Get product details separately
        try {
          final productResponse = await _supabase
              .from('grn_master_items')
              .select('item_name, item_code, uom')
              .eq('id', itemData['product_id'])
              .maybeSingle();
          
          // Merge product data with item data
          final mergedData = Map<String, dynamic>.from(itemData);
          if (productResponse != null) {
            mergedData['grn_master_items'] = productResponse;
          }
          
          items.add(SimpleWriteOffItem.fromMap(mergedData));
        } catch (e) {
          debugPrint('⚠️ Could not get product details for ${itemData['product_id']}: $e');
          // Add item without product details
          items.add(SimpleWriteOffItem.fromMap(itemData));
        }
      }

      debugPrint('📋 Write-off items loaded: ${items.length} for write-off: $writeOffId');
      return items;
    } catch (e) {
      debugPrint('❌ Get write-off items error: $e');
      return [];
    }
  }

  /// Get write off details with items
  Future<SimpleWriteOffHeader?> getWriteOffDetails(String writeOffId) async {
    try {
      final headerResponse = await _supabase
          .from('write_off_headers')
          .select('''
            *,
            requested_user:app_users!requested_by(full_name)
          ''')
          .eq('id', writeOffId)
          .single();

      // Get items using the fixed method
      final items = await getWriteOffItems(writeOffId);

      return SimpleWriteOffHeader.fromMap(headerResponse, items);
    } catch (e) {
      debugPrint('❌ Get simple write off details error: $e');
      return null;
    }
  }

  /// Reduce stock for write-off with unit conversion support
  Future<void> _reduceStockForWriteOff({
    required String storeId,
    required String productId,
    required String productName,
    required double writeOffQuantity,
    required String writeOffUnit,
    required String writeOffId,
    required String writeOffReason,
    String? userId,
  }) async {
    try {
      // Get current stock level and its unit
      final stockResponse = await _supabase
          .from('raw_material_stock_status')
          .select('current_stock, unit')
          .eq('store_id', storeId)
          .eq('grn_item_id', productId)
          .maybeSingle();

      if (stockResponse == null) {
        debugPrint('⚠️ No stock record found for write-off: $productName');
        return;
      }

      final currentQty = (stockResponse['current_stock'] as num?)?.toDouble() ?? 0;
      final stockUnit = stockResponse['unit'] as String? ?? 'PCS';

      // Convert write-off quantity to stock unit if needed
      double convertedWriteOffQty = writeOffQuantity;
      
      if (writeOffUnit.toUpperCase() != stockUnit.toUpperCase()) {
        final converted = UnitConversionService.convertQuantity(
          quantity: writeOffQuantity,
          fromUnit: writeOffUnit,
          toUnit: stockUnit,
        );
        
        if (converted == null) {
          debugPrint('❌ Cannot convert $writeOffUnit to $stockUnit for $productName');
          debugPrint('⚠️ Using original quantity without conversion');
          // You might want to throw an exception here or handle this case differently
        } else {
          convertedWriteOffQty = converted;
          debugPrint('🔄 Write-off unit conversion: ${UnitConversionService.formatQuantity(writeOffQuantity, writeOffUnit)} $writeOffUnit = ${UnitConversionService.formatQuantity(convertedWriteOffQty, stockUnit)} $stockUnit');
        }
      }

      if (currentQty < convertedWriteOffQty) {
        debugPrint('⚠️ Insufficient stock for write-off $productName: Available=${UnitConversionService.formatQuantity(currentQty, stockUnit)} $stockUnit, Write-off=${UnitConversionService.formatQuantity(convertedWriteOffQty, stockUnit)} $stockUnit');
        // You might want to throw an exception here or handle this case differently
      }

      final newCurrentQty = currentQty - convertedWriteOffQty;

      // Update stock levels
      await _supabase
          .from('raw_material_stock_status')
          .update({
            'current_stock': newCurrentQty,
            'last_updated': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('store_id', storeId)
          .eq('grn_item_id', productId);

      // Record stock movement with converted quantity
      await _recordWriteOffStockMovement(
        storeId: storeId,
        productId: productId,
        writeOffId: writeOffId,
        quantityBefore: currentQty,
        quantityChange: -convertedWriteOffQty,
        quantityAfter: newCurrentQty,
        writeOffReason: writeOffReason,
        remarks: 'Write-off: $writeOffReason (${UnitConversionService.formatQuantity(writeOffQuantity, writeOffUnit)} $writeOffUnit converted to ${UnitConversionService.formatQuantity(convertedWriteOffQty, stockUnit)} $stockUnit) - Unit: $stockUnit',
        userId: userId,
      );

      debugPrint('📉 Stock reduced for write-off: $productName by ${UnitConversionService.formatQuantity(convertedWriteOffQty, stockUnit)} $stockUnit (New: ${UnitConversionService.formatQuantity(newCurrentQty, stockUnit)} $stockUnit)');
    } catch (e) {
      debugPrint('❌ Write-off stock reduction error for $productName: $e');
    }
  }

  /// Record stock movement for write-off
  Future<void> _recordWriteOffStockMovement({
    required String storeId,
    required String productId,
    required String writeOffId,
    required double quantityBefore,
    required double quantityChange,
    required double quantityAfter,
    required String writeOffReason,
    String? remarks,
    String? userId,
  }) async {
    try {
      await _supabase.from('stock_movements').insert({
        'store_id': storeId,
        'product_id': productId,
        'movement_type': 'write_off',
        'reference_type': 'write_off',
        'reference_id': writeOffId,
        'quantity_before': quantityBefore,
        'quantity_change': quantityChange,
        'quantity_after': quantityAfter,
        'remarks': remarks,
        'movement_date': DateTime.now().toIso8601String(),
        'created_by': userId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Write-off stock movement recording error: $e');
    }
  }
}