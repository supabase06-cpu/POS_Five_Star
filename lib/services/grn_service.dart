import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item_model.dart';

class GrnService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all GRN master items (raw materials) for selection
  Future<List<RawMaterial>> getRawMaterials({
    required String orgId,
    String? searchQuery,
  }) async {
    try {
      debugPrint('🔍 Fetching raw materials with stock for org: $orgId');
      
      var query = _supabase
          .from('grn_master_items')
          .select('''
            id,
            item_code,
            item_name,
            short_name,
            uom,
            cost_price,
            raw_material_stock_status!left(current_stock, unit_cost)
          ''')
          .eq('org_id', orgId)
          .eq('is_active', true)
          .eq('raw_material_stock_status.store_id', orgId);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%');
      }

      final response = await query.order('item_name');

      final rawMaterials = (response as List).map<RawMaterial>((json) {
        // Get stock from the joined table
        final stockData = json['raw_material_stock_status'] as List?;
        double currentStock = 0.0;
        double unitCost = (json['cost_price'] as num?)?.toDouble() ?? 0.0;
        
        if (stockData != null && stockData.isNotEmpty) {
          final stockInfo = stockData.first;
          currentStock = (stockInfo['current_stock'] as num?)?.toDouble() ?? 0.0;
          // Use unit cost from stock if available, otherwise fallback to cost_price
          unitCost = (stockInfo['unit_cost'] as num?)?.toDouble() ?? unitCost;
        }
        
        debugPrint('📦 ${json['item_name']}: Stock = $currentStock ${json['uom']}');
        
        return RawMaterial(
          id: json['id'],
          itemCode: json['item_code'] ?? '',
          itemName: json['item_name'] ?? '',
          shortName: json['short_name'],
          uom: json['uom'] ?? 'PCS',
          costPrice: unitCost,
          currentStock: currentStock,
        );
      }).toList();

      debugPrint('🥩 Raw materials loaded: ${rawMaterials.length}');
      return rawMaterials;
    } catch (e) {
      debugPrint('❌ Error fetching raw materials: $e');
      // Fallback to basic query without stock if the join fails
      return _getRawMaterialsFallback(orgId: orgId, searchQuery: searchQuery);
    }
  }

  /// Fallback method without stock information
  Future<List<RawMaterial>> _getRawMaterialsFallback({
    required String orgId,
    String? searchQuery,
  }) async {
    try {
      debugPrint('🔄 Using fallback method for raw materials');
      
      var query = _supabase
          .from('grn_master_items')
          .select('''
            id,
            item_code,
            item_name,
            short_name,
            uom,
            cost_price
          ''')
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%');
      }

      final response = await query.order('item_name');

      final rawMaterials = (response as List).map<RawMaterial>((json) {
        return RawMaterial(
          id: json['id'],
          itemCode: json['item_code'] ?? '',
          itemName: json['item_name'] ?? '',
          shortName: json['short_name'],
          uom: json['uom'] ?? 'PCS',
          costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
          currentStock: 0.0, // No stock info in fallback
        );
      }).toList();

      debugPrint('🥩 Raw materials (fallback): ${rawMaterials.length}');
      return rawMaterials;
    } catch (e) {
      debugPrint('❌ Raw materials fallback error: $e');
      return [];
    }
  }

  /// Get raw materials by IDs (for displaying selected materials)
  Future<List<RawMaterial>> getRawMaterialsByIds({
    required String orgId,
    required List<String> materialIds,
  }) async {
    if (materialIds.isEmpty) return [];

    try {
      debugPrint('🔍 Fetching raw materials by IDs with stock for org: $orgId');
      
      final response = await _supabase
          .from('grn_master_items')
          .select('''
            id,
            item_code,
            item_name,
            short_name,
            uom,
            cost_price,
            raw_material_stock_status!left(current_stock, unit_cost)
          ''')
          .eq('org_id', orgId)
          .eq('raw_material_stock_status.store_id', orgId)
          .filter('id', 'in', '(${materialIds.map((id) => '"$id"').join(',')})');

      final rawMaterials = (response as List).map<RawMaterial>((json) {
        // Get stock from the joined table
        final stockData = json['raw_material_stock_status'] as List?;
        double currentStock = 0.0;
        double unitCost = (json['cost_price'] as num?)?.toDouble() ?? 0.0;
        
        if (stockData != null && stockData.isNotEmpty) {
          final stockInfo = stockData.first;
          currentStock = (stockInfo['current_stock'] as num?)?.toDouble() ?? 0.0;
          // Use unit cost from stock if available, otherwise fallback to cost_price
          unitCost = (stockInfo['unit_cost'] as num?)?.toDouble() ?? unitCost;
        }
        
        debugPrint('📦 ${json['item_name']}: Stock = $currentStock ${json['uom']}');
        
        return RawMaterial(
          id: json['id'],
          itemCode: json['item_code'] ?? '',
          itemName: json['item_name'] ?? '',
          shortName: json['short_name'],
          uom: json['uom'] ?? 'PCS',
          costPrice: unitCost,
          currentStock: currentStock,
        );
      }).toList();

      return rawMaterials;
    } catch (e) {
      debugPrint('❌ Get raw materials by IDs error: $e');
      // Fallback to basic query without stock
      return _getRawMaterialsByIdsFallback(orgId: orgId, materialIds: materialIds);
    }
  }

  /// Fallback method for getRawMaterialsByIds without stock information
  Future<List<RawMaterial>> _getRawMaterialsByIdsFallback({
    required String orgId,
    required List<String> materialIds,
  }) async {
    try {
      debugPrint('🔄 Using fallback method for raw materials by IDs');
      
      final response = await _supabase
          .from('grn_master_items')
          .select('''
            id,
            item_code,
            item_name,
            short_name,
            uom,
            cost_price
          ''')
          .eq('org_id', orgId)
          .filter('id', 'in', '(${materialIds.map((id) => '"$id"').join(',')})');

      final rawMaterials = (response as List).map<RawMaterial>((json) {
        return RawMaterial(
          id: json['id'],
          itemCode: json['item_code'] ?? '',
          itemName: json['item_name'] ?? '',
          shortName: json['short_name'],
          uom: json['uom'] ?? 'PCS',
          costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
          currentStock: 0.0, // No stock info in fallback
        );
      }).toList();

      return rawMaterials;
    } catch (e) {
      debugPrint('❌ Get raw materials by IDs fallback error: $e');
      return [];
    }
  }
}