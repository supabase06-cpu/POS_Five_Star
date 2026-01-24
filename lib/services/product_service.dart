import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item_model.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  static const int pageSize = 20;

  /// Get paginated products for the organization
  Future<ProductsResponse> getProducts({
    required String orgId,
    int page = 1,
    String? searchQuery,
    String? categoryId,
  }) async {
    try {
      final from = (page - 1) * pageSize;
      final to = from + pageSize - 1;
      
      var query = _supabase
          .from('items')
          .select('*, category:item_categories(*), raw_material_mapping, total_pieces_limit')
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%');
      }

      final response = await query
          .order('display_order')
          .order('item_name')
          .range(from, to);

      final items = (response as List)
          .map<Item>((json) => Item.fromJson(json))
          .toList();
      
      final countResponse = await _getProductCount(orgId, searchQuery, categoryId);

      debugPrint('📦 Products: ${items.length}/${countResponse} (page $page)');
      
      return ProductsResponse(
        items: items,
        totalCount: countResponse,
        currentPage: page,
        totalPages: countResponse > 0 ? (countResponse / pageSize).ceil() : 1,
        hasMore: to < countResponse - 1,
      );
    } catch (e) {
      debugPrint('❌ Products error: $e');
      return ProductsResponse(
        items: [],
        totalCount: 0,
        currentPage: page,
        totalPages: 0,
        hasMore: false,
      );
    }
  }

  Future<int> _getProductCount(String orgId, String? searchQuery, String? categoryId) async {
    try {
      var query = _supabase
          .from('items')
          .select('id')
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('item_name.ilike.%$searchQuery%,item_code.ilike.%$searchQuery%');
      }

      final result = await query;
      return (result as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Update product with raw materials mapping and pieces limit
  Future<bool> updateProduct({
    required String productId,
    required String orgId,
    String? itemName,
    double? sellingPrice,
    String? imageUrl,
    List<Map<String, dynamic>>? rawMaterialMapping,
    int? totalPiecesLimit,
    // Additional fields for comprehensive editing
    double? costPrice,
    double? taxRate,
    String? hsnCode,
    int? minStockLevel,
    int? maxStockLevel,
    int? reorderLevel,
    bool? isVeg,
    bool? isCombo,
  }) async {
    try {
      debugPrint('🔄 PRODUCT_SERVICE: Starting updateProduct...');
      debugPrint('🔄 PRODUCT_SERVICE: Product ID: $productId');
      debugPrint('🔄 PRODUCT_SERVICE: Org ID: $orgId');
      debugPrint('🔄 PRODUCT_SERVICE: Item Name: $itemName');
      debugPrint('🔄 PRODUCT_SERVICE: Raw Material Mapping: $rawMaterialMapping');
      
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (itemName != null) updates['item_name'] = itemName;
      if (sellingPrice != null) updates['selling_price'] = sellingPrice;
      if (imageUrl != null) updates['image_url'] = imageUrl;
      if (rawMaterialMapping != null) {
        updates['raw_material_mapping'] = rawMaterialMapping.isEmpty ? null : rawMaterialMapping;
        debugPrint('🔄 PRODUCT_SERVICE: Setting raw_material_mapping to: ${updates['raw_material_mapping']}');
      }
      if (totalPiecesLimit != null) {
        updates['total_pieces_limit'] = totalPiecesLimit;
      }
      
      // Additional fields for comprehensive editing
      if (costPrice != null) updates['cost_price'] = costPrice;
      if (taxRate != null) updates['tax_rate'] = taxRate;
      if (hsnCode != null) updates['hsn_code'] = hsnCode.isEmpty ? null : hsnCode;
      if (minStockLevel != null) updates['min_stock_level'] = minStockLevel;
      if (maxStockLevel != null) updates['max_stock_level'] = maxStockLevel;
      if (reorderLevel != null) updates['reorder_level'] = reorderLevel;
      if (isVeg != null) updates['is_veg'] = isVeg;
      if (isCombo != null) updates['is_combo'] = isCombo;

      debugPrint('🔄 PRODUCT_SERVICE: Final updates object: $updates');
      debugPrint('🔄 PRODUCT_SERVICE: Executing Supabase update...');

      final response = await _supabase
          .from('items')
          .update(updates)
          .eq('id', productId)
          .eq('org_id', orgId)
          .select(); // Add select to get the updated row

      debugPrint('🔄 PRODUCT_SERVICE: Supabase response: $response');
      debugPrint('✅ PRODUCT_SERVICE: Product updated successfully');
      return true;
    } catch (e) {
      debugPrint('❌ PRODUCT_SERVICE: Update error: $e');
      debugPrint('❌ PRODUCT_SERVICE: Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        debugPrint('❌ PRODUCT_SERVICE: Postgrest error details: ${e.details}');
        debugPrint('❌ PRODUCT_SERVICE: Postgrest error hint: ${e.hint}');
        debugPrint('❌ PRODUCT_SERVICE: Postgrest error code: ${e.code}');
      }
      return false;
    }
  }

  /// Upload product image to Supabase Storage
  Future<String?> uploadProductImage({
    required String orgId,
    required String productId,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    try {
      final extension = fileName.split('.').last.toLowerCase();
      final path = '$orgId/products/$productId.$extension';
      
      await _supabase.storage
          .from('product-images')
          .uploadBinary(
            path,
            imageBytes,
            fileOptions: FileOptions(
              contentType: 'image/$extension',
              upsert: true,
            ),
          );

      final signedUrl = await _supabase.storage
          .from('product-images')
          .createSignedUrl(path, 60 * 60 * 24 * 365);

      debugPrint('✅ Image uploaded');
      return signedUrl;
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      return null;
    }
  }

  /// Delete product image from storage
  Future<bool> deleteProductImage({
    required String orgId,
    required String productId,
    required String currentImageUrl,
  }) async {
    try {
      final uri = Uri.parse(currentImageUrl);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf('product-images');
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        final path = pathSegments.sublist(bucketIndex + 1).join('/');
        await _supabase.storage.from('product-images').remove([path]);
        debugPrint('✅ Image deleted');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
      return false;
    }
  }

  /// Get all categories for filtering
  Future<List<ItemCategory>> getCategories(String orgId) async {
    try {
      final response = await _supabase
          .from('item_categories')
          .select('*')
          .eq('org_id', orgId)
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final categories = (response as List)
          .map<ItemCategory>((json) => ItemCategory.fromJson(json))
          .toList();
      
      debugPrint('📂 Categories: ${categories.length}');
      return categories;
    } catch (e) {
      debugPrint('❌ Categories error: $e');
      return [];
    }
  }

  /// Create a new product in the items table
  Future<bool> createProduct({
    required String orgId,
    String? categoryId,
    required String itemCode,
    required String itemName,
    String? shortName,
    String? description,
    String unit = 'PCS',
    String? hsnCode,
    double costPrice = 0,
    required double sellingPrice,
    double? mrp,
    double taxRate = 5.00,
    bool taxInclusive = true,
    int minStockLevel = 10,
    int maxStockLevel = 1000,
    int reorderLevel = 20,
    bool isCombo = false,
    bool isVeg = false,
    bool isAvailable = true,
    String? imageUrl,
    String? barcode,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    try {
      debugPrint('📝 Creating product: $itemName ($itemCode)');
      
      await _supabase.from('items').insert({
        'org_id': orgId,
        'category_id': categoryId,
        'item_code': itemCode,
        'item_name': itemName,
        'short_name': shortName,
        'description': description,
        'unit': unit,
        'hsn_code': hsnCode,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'mrp': mrp,
        'tax_rate': taxRate,
        'tax_inclusive': taxInclusive,
        'min_stock_level': minStockLevel,
        'max_stock_level': maxStockLevel,
        'reorder_level': reorderLevel,
        'is_combo': isCombo,
        'is_veg': isVeg,
        'is_available': isAvailable,
        'image_url': imageUrl,
        'barcode': barcode,
        'display_order': displayOrder,
        'is_active': isActive,
      });
      
      debugPrint('✅ Product created: $itemName');
      return true;
    } catch (e) {
      debugPrint('❌ Create product error: $e');
      return false;
    }
  }

  /// Check if product code already exists
  Future<bool> checkDuplicateProductCode(String orgId, String itemCode) async {
    try {
      final response = await _supabase
          .from('items')
          .select('id')
          .eq('org_id', orgId)
          .eq('item_code', itemCode)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      debugPrint('❌ Check duplicate product code error: $e');
      return false;
    }
  }
}

class ProductsResponse {
  final List<Item> items;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final bool hasMore;

  ProductsResponse({
    required this.items,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    required this.hasMore,
  });
}