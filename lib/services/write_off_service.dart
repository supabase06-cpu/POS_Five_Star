import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/write_off_model.dart';
import '../models/inward_model.dart';

class WriteOffService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get products with available stock for write off
  Future<List<InwardProduct>> getProductsForWriteOff(String orgId, {String? searchQuery}) async {
    try {
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
      
      final products = response.map<InwardProduct>((item) {
        final grnItem = item['grn_master_items'];
        final availableQty = (item['current_stock'] as num?)?.toDouble() ?? 0;
        
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

      debugPrint('🔍 Products available for write off: ${products.length}');
      return products;
    } catch (e) {
      debugPrint('❌ Get products for write off error: $e');
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

  /// Create write off
  Future<String?> createWriteOff({
    required String storeId,
    required String writeOffNumber,
    required DateTime writeOffDate,
    required String writeOffReason,
    required double subTotal,
    required double totalAmount,
    required String requestedBy,
    String? remarks,
    required List<WriteOffCartItem> items,
  }) async {
    try {
      debugPrint('📝 Creating write off: $writeOffNumber');

      // Create header
      final headerResponse = await _supabase
          .from('write_off_headers')
          .insert({
            'store_id': storeId,
            'write_off_number': writeOffNumber,
            'write_off_date': writeOffDate.toIso8601String().split('T')[0],
            'sub_total': subTotal,
            'total_write_off_amount': totalAmount,
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
          'total_amount': item.totalAmount,
          'item_condition': item.writeOffReason,
          'remarks': item.remarks,
          'created_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await _supabase.from('write_off_items').insert(itemsData);

      debugPrint('✅ Write off created: $writeOffNumber');
      return writeOffId;
    } catch (e) {
      debugPrint('❌ Create write off error: $e');
      return null;
    }
  }

  /// Get write off history
  Future<List<WriteOffHeader>> getWriteOffHistory({
    required String storeId,
    int page = 1,
    int limit = 20,
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
            requested_user:app_users!requested_by(full_name),
            approved_user:app_users!approved_by(full_name)
          ''')
          .eq('store_id', storeId);

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
          .map<WriteOffHeader>((data) => WriteOffHeader.fromMap(data))
          .toList();

      debugPrint('📋 Write offs loaded: ${writeOffs.length}');
      return writeOffs;
    } catch (e) {
      debugPrint('❌ Get write off history error: $e');
      return [];
    }
  }

  /// Get write off details with items
  Future<WriteOffHeader?> getWriteOffDetails(String writeOffId) async {
    try {
      final headerResponse = await _supabase
          .from('write_off_headers')
          .select('''
            *,
            requested_user:app_users!requested_by(full_name),
            approved_user:app_users!approved_by(full_name)
          ''')
          .eq('id', writeOffId)
          .single();

      final itemsResponse = await _supabase
          .from('write_off_items')
          .select('''
            *,
            grn_master_items(item_name, item_code)
          ''')
          .eq('write_off_id', writeOffId)
          .order('created_at');

      final items = (itemsResponse as List)
          .map<WriteOffItem>((data) => WriteOffItem.fromMap(data))
          .toList();

      return WriteOffHeader.fromMap(headerResponse, items);
    } catch (e) {
      debugPrint('❌ Get write off details error: $e');
      return null;
    }
  }
}