import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inward_model.dart';

class InwardService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ============ SUPPLIERS ============

  /// Get all active suppliers for org
  Future<List<Supplier>> getSuppliers(String orgId, {String? searchQuery}) async {
    try {
      debugPrint('🔍 Fetching suppliers for org: $orgId');
      
      var query = _supabase
          .from('suppliers')
          .select()
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('supplier_name.ilike.%$searchQuery%,supplier_code.ilike.%$searchQuery%,phone.ilike.%$searchQuery%');
      }

      final response = await query.order('supplier_name');
      debugPrint('📥 Suppliers response: ${response.length} records');
      final suppliers = response.map<Supplier>((s) => Supplier.fromMap(s)).toList();
      debugPrint('📦 Suppliers loaded: ${suppliers.length}');
      return suppliers;
    } catch (e) {
      debugPrint('❌ Get suppliers error: $e');
      return [];
    }
  }

  /// Get supplier by ID
  Future<Supplier?> getSupplierById(String supplierId) async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select()
          .eq('id', supplierId)
          .single();
      debugPrint('✅ Supplier found: ${response['supplier_name']}');
      return Supplier.fromMap(response);
    } catch (e) {
      debugPrint('❌ Get supplier error: $e');
      return null;
    }
  }

  // ============ PRODUCTS ============

  /// Create a new product with complete details
  Future<bool> createProductWithDetails({
    required String orgId,
    required String productCode,
    required String productName,
    required String hsnCode,
    required String uom,
    required double costPrice,
    required double sellingPrice,
    required double taxPercentage,
    required bool isVeg,
    required bool isCombo,
    required bool isPerishable,
    required int minStockLevel,
    required int maxStockLevel,
    required int reorderLevel,
    int? shelfLifeDays,
    String? storageInstructions,
  }) async {
    try {
      debugPrint('📝 Creating GRN item with details: $productName ($productCode)');
      
      await _supabase.from('grn_master_items').insert({
        'org_id': orgId,
        'item_code': productCode,
        'item_name': productName,
        'hsn_code': hsnCode,
        'uom': uom,
        'cost_price': costPrice,
        'tax_percentage': taxPercentage,
        'min_stock_level': minStockLevel,
        'max_stock_level': maxStockLevel,
        'reorder_level': reorderLevel,
        'is_perishable': isPerishable,
        'shelf_life_days': shelfLifeDays,
        'storage_instructions': storageInstructions,
        'is_active': true,
      });
      
      debugPrint('✅ GRN item created with details: $productName');
      return true;
    } catch (e) {
      debugPrint('❌ Create GRN item with details error: $e');
      return false;
    }
  }

  /// Create a new product (legacy method)
  Future<bool> createProduct({
    required String orgId,
    required String productCode,
    required String productName,
    required String uom,
    required double costPrice,
    required double sellingPrice,
    double taxPercentage = 5,
  }) async {
    try {
      debugPrint('📝 Creating GRN item: $productName ($productCode)');
      
      await _supabase.from('grn_master_items').insert({
        'org_id': orgId,
        'item_code': productCode,
        'item_name': productName,
        'uom': uom,
        'cost_price': costPrice,
        'tax_percentage': taxPercentage,
        'is_active': true,
      });
      
      debugPrint('✅ GRN item created: $productName');
      return true;
    } catch (e) {
      debugPrint('❌ Create GRN item error: $e');
      return false;
    }
  }

  /// Check if product code already exists
  Future<bool> checkDuplicateProductCode(String orgId, String productCode) async {
    try {
      final response = await _supabase
          .from('grn_master_items')
          .select('id')
          .eq('org_id', orgId)
          .eq('item_code', productCode)
          .limit(1);
      
      final exists = response.isNotEmpty;
      if (exists) {
        debugPrint('⚠️ Duplicate GRN item code: $productCode');
      }
      return exists;
    } catch (e) {
      debugPrint('❌ Check duplicate GRN item error: $e');
      return false;
    }
  }

  /// Get products for inward selection (from grn_master_items table)
  Future<List<InwardProduct>> getProducts(String orgId, {String? searchQuery, String? categoryId}) async {
    try {
      var query = _supabase
          .from('grn_master_items')
          .select('*, categories(category_name)')
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%,barcode.ilike.%$searchQuery%');
      }

      final response = await query.order('item_name').limit(50);
      final products = response.map<InwardProduct>((p) => InwardProduct.fromGrnItem(p)).toList();
      debugPrint('🔍 GRN items found: ${products.length} for query: $searchQuery');
      return products;
    } catch (e) {
      debugPrint('❌ Get GRN items error: $e');
      return [];
    }
  }

  // ============ GRN NUMBER ============

  /// Check if invoice already exists for supplier
  Future<bool> checkDuplicateInvoice(String storeId, String supplierId, String invoiceNo) async {
    try {
      final response = await _supabase
          .from('inward_headers')
          .select('id')
          .eq('store_id', storeId)
          .eq('supplier_id', supplierId)
          .eq('supplier_invoice_no', invoiceNo)
          .limit(1);
      
      final exists = response.isNotEmpty;
      if (exists) {
        debugPrint('⚠️ Duplicate invoice found: $invoiceNo for supplier $supplierId');
      }
      return exists;
    } catch (e) {
      debugPrint('❌ Check duplicate invoice error: $e');
      return false;
    }
  }

  /// Generate next GRN number
  Future<String> generateGrnNumber(String storeId) async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

      // Get count of GRNs for today
      final result = await _supabase
          .from('inward_headers')
          .select('id')
          .eq('store_id', storeId)
          .gte('received_date', today.toIso8601String().split('T')[0])
          .count();

      final count = (result.count ?? 0) + 1;
      final grnNumber = 'GRN-$dateStr-${count.toString().padLeft(4, '0')}';
      debugPrint('📝 Generated GRN: $grnNumber');
      return grnNumber;
    } catch (e) {
      debugPrint('❌ Generate GRN error: $e');
      final timestamp = DateTime.now().millisecondsSinceEpoch % 10000;
      return 'GRN-${DateTime.now().toIso8601String().split('T')[0].replaceAll('-', '')}-$timestamp';
    }
  }

  // ============ INWARD CRUD ============

  /// Create new inward (GRN)
  Future<String?> createInward({
    required String storeId,
    required String supplierId,
    required String grnNumber,
    String? supplierInvoiceNo,
    required DateTime receivedDate,
    DateTime? invoiceDate,
    required double subTotal,
    required double discountAmount,
    required double taxAmount,
    required double totalAmount,
    required String receivedBy,
    String? remarks,
    required List<InwardCartItem> items,
  }) async {
    try {
      debugPrint('📝 Creating inward GRN: $grnNumber');
      debugPrint('   Supplier: $supplierId');
      debugPrint('   Items: ${items.length}');
      debugPrint('   Total: ₹$totalAmount');

      // Insert header
      final headerResponse = await _supabase.from('inward_headers').insert({
        'store_id': storeId,
        'supplier_id': supplierId,
        'grn_number': grnNumber,
        'supplier_invoice_no': supplierInvoiceNo,
        'received_date': receivedDate.toIso8601String().split('T')[0],
        'invoice_date': invoiceDate?.toIso8601String().split('T')[0],
        'sub_total': subTotal,
        'discount_amount': discountAmount,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'status': 'posted',
        'received_by': receivedBy,
        'remarks': remarks,
        'sync_status': 'synced',
        'synced_at': DateTime.now().toIso8601String(),
      }).select('id').single();

      final inwardId = headerResponse['id'] as String;
      debugPrint('✅ Inward header created: $inwardId');

      // Insert items
      int lineNumber = 1;
      for (var item in items) {
        await _supabase.from('inward_items').insert({
          'inward_id': inwardId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'uom': item.product.uom,
          'unit_cost': item.unitCost,
          'discount_percentage': item.discountPercentage,
          'discount_amount': item.discountAmount,
          'taxable_amount': item.taxableAmount,
          'cgst_percentage': item.cgstPercentage,
          'cgst_amount': item.cgstAmount,
          'sgst_percentage': item.sgstPercentage,
          'sgst_amount': item.sgstAmount,
          'total_cost': item.totalCost,
          'batch_no': item.batchNo,
          'manufacturing_date': item.manufacturingDate?.toIso8601String().split('T')[0],
          'expiry_date': item.expiryDate?.toIso8601String().split('T')[0],
          'open_date': item.openDate?.toIso8601String().split('T')[0],
          'line_number': lineNumber++,
        });

        // Stock levels are now updated automatically by database triggers
        debugPrint('📦 Item added: ${item.product.productName} qty: ${item.quantity}');
      }

      debugPrint('✅ Inward completed: $grnNumber with ${items.length} items');
      return grnNumber;
    } catch (e) {
      debugPrint('❌ Create inward error: $e');
      return null;
    }
  }

  /// Update stock level after inward - DEPRECATED: Now handled by database triggers
  /// This function is kept for reference but not used anymore
  /*
  Future<void> _updateStockLevel(String storeId, String grnItemId, double quantity, double unitCost, String inwardId, String userId) async {
    // This function is no longer needed as database triggers handle stock updates automatically
    // when inward_items are inserted. The unified_stock_update_on_inward trigger will:
    // 1. Update raw_material_stock_status table
    // 2. Create stock_movements records
    // 3. Handle all stock calculations
    debugPrint('📦 Stock update handled by database triggers');
  }
  */

  // ============ INWARD LIST ============

  /// Get inward list by date range
  Future<List<InwardHeader>> getInwardList(String storeId, {DateTime? fromDate, DateTime? toDate}) async {
    try {
      final from = fromDate ?? DateTime.now().subtract(const Duration(days: 30));
      final to = toDate ?? DateTime.now();

      debugPrint('📊 Fetching inwards: ${from.toIso8601String().split('T')[0]} to ${to.toIso8601String().split('T')[0]}');

      final response = await _supabase
          .from('inward_headers')
          .select('*, suppliers(supplier_name), app_users!inward_headers_received_by_fkey(full_name), inward_items(*, grn_master_items(item_name, item_code))')
          .eq('store_id', storeId)
          .gte('received_date', from.toIso8601String().split('T')[0])
          .lte('received_date', to.toIso8601String().split('T')[0])
          .order('received_date', ascending: false)
          .order('created_at', ascending: false);

      final inwards = <InwardHeader>[];
      for (var headerData in response) {
        final items = (headerData['inward_items'] as List?)
                ?.map((item) => InwardItem.fromMap(item as Map<String, dynamic>))
                .toList() ??
            [];
        inwards.add(InwardHeader.fromMap(headerData as Map<String, dynamic>, items));
      }
      
      debugPrint('📋 Inwards loaded: ${inwards.length}');
      return inwards;
    } catch (e) {
      debugPrint('❌ Get inward list error: $e');
      return [];
    }
  }

  /// Get inward details with items
  Future<InwardHeader?> getInwardDetails(String inwardId) async {
    try {
      debugPrint('🔍 Loading inward details: $inwardId');
      
      final headerResponse = await _supabase
          .from('inward_headers')
          .select('*, suppliers(supplier_name), app_users!inward_headers_received_by_fkey(full_name)')
          .eq('id', inwardId)
          .single();

      final itemsResponse = await _supabase
          .from('inward_items')
          .select('*, grn_master_items(item_name, item_code)')
          .eq('inward_id', inwardId)
          .order('line_number');

      final items = itemsResponse.map<InwardItem>((i) => InwardItem.fromMap(i)).toList();
      debugPrint('✅ Inward details loaded: ${items.length} items');
      return InwardHeader.fromMap(headerResponse, items);
    } catch (e) {
      debugPrint('❌ Get inward details error: $e');
      return null;
    }
  }

  // ============ SUMMARY ============

  /// Get inward summary for date range
  Future<InwardSummary> getInwardSummary(String storeId, {DateTime? fromDate, DateTime? toDate}) async {
    try {
      final from = fromDate ?? DateTime.now();
      final to = toDate ?? DateTime.now();

      final response = await _supabase
          .from('inward_headers')
          .select('id, total_amount, status')
          .eq('store_id', storeId)
          .gte('received_date', from.toIso8601String().split('T')[0])
          .lte('received_date', to.toIso8601String().split('T')[0]);

      int totalCount = 0;
      double totalAmount = 0;
      int postedCount = 0;
      int draftCount = 0;

      for (var row in response) {
        totalCount++;
        totalAmount += (row['total_amount'] as num?)?.toDouble() ?? 0;
        if (row['status'] == 'posted') {
          postedCount++;
        } else if (row['status'] == 'draft') {
          draftCount++;
        }
      }

      debugPrint('📊 Inward summary: $totalCount GRNs, ₹$totalAmount total');
      return InwardSummary(
        totalCount: totalCount,
        totalAmount: totalAmount,
        postedCount: postedCount,
        draftCount: draftCount,
      );
    } catch (e) {
      debugPrint('❌ Get inward summary error: $e');
      return InwardSummary();
    }
  }
}

/// Inward summary model
class InwardSummary {
  final int totalCount;
  final double totalAmount;
  final int postedCount;
  final int draftCount;

  InwardSummary({
    this.totalCount = 0,
    this.totalAmount = 0,
    this.postedCount = 0,
    this.draftCount = 0,
  });
}
