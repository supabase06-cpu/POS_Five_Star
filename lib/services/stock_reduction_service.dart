import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/item_model.dart';
import 'unit_conversion_service.dart';
import 'local_db_service.dart';

class StockReductionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDbService _localDb = LocalDbService();

  /// Check if online
  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Reduce raw material stock when finished product is sold (offline-first)
  Future<Map<String, dynamic>> reduceStockForSale({
    required String storeId,
    required String productId,
    required double soldQuantity,
    required String salesOrderId,
    String? userId,
  }) async {
    try {
      // Get product with raw material mapping from local DB first
      Map<String, dynamic>? productData;
      final isOnline = await _isOnline();
      
      debugPrint('🔍 Stock reduction for product $productId (${isOnline ? 'online' : 'offline'})');
      
      if (isOnline) {
        try {
          final productResponse = await _supabase
              .from('items')
              .select('raw_material_mapping, item_name, org_id')
              .eq('id', productId)
              .eq('org_id', storeId)
              .eq('is_active', true)
              .single();
          productData = productResponse;
          debugPrint('✅ Got product data from cloud');
        } catch (e) {
          debugPrint('⚠️ Failed to get product from cloud, using local data: $e');
        }
      }
      
      // Fallback to local product data if cloud fails or offline
      if (productData == null) {
        final localProduct = await _getLocalProductData(productId);
        if (localProduct == null) {
          debugPrint('❌ Product not found in local database');
          return {
            'success': false,
            'hasMapping': false,
            'error': 'Product not found in local database'
          };
        }
        productData = localProduct;
        debugPrint('✅ Got product data from local DB');
      }

      final rawMaterialMapping = productData['raw_material_mapping'] as List?;
      if (rawMaterialMapping == null || rawMaterialMapping.isEmpty) {
        debugPrint('⚠️ No raw material mapping found for product: ${productData['item_name']}');
        return {
          'success': true,
          'hasMapping': false,
          'productName': productData['item_name'],
          'message': 'No raw material mapping found'
        };
      }

      // Process each raw material in the mapping
      for (final mappingData in rawMaterialMapping) {
        final mapping = RawMaterialMapping.fromJson(mappingData);
        final totalReduction = mapping.quantity * soldQuantity;

        await _reduceRawMaterialStock(
          storeId: storeId,
          materialId: mapping.materialId,
          materialName: mapping.materialName,
          materialCode: mapping.materialCode ?? '',
          reductionQuantity: totalReduction,
          mappingUnit: mapping.uom,
          salesOrderId: salesOrderId,
          userId: userId,
        );
      }

      debugPrint('✅ Stock reduced for ${rawMaterialMapping.length} raw materials');
      return {
        'success': true,
        'hasMapping': true,
        'productName': productData['item_name'],
        'materialsProcessed': rawMaterialMapping.length
      };
    } catch (e) {
      debugPrint('❌ Stock reduction error: $e');
      return {
        'success': false,
        'hasMapping': false,
        'error': e.toString()
      };
    }
  }

  /// Get product data from local database
  Future<Map<String, dynamic>?> _getLocalProductData(String productId) async {
    final db = await _localDb.database;
    
    final result = await db.query(
      'local_products',
      where: 'id = ?',
      whereArgs: [productId],
    );
    
    if (result.isEmpty) {
      debugPrint('❌ Product $productId not found in local DB');
      return null;
    }
    
    final product = result.first;
    
    // Parse raw_material_mapping from JSON string
    List<dynamic> rawMaterialMapping = [];
    if (product['raw_material_mapping'] != null) {
      try {
        final mappingStr = product['raw_material_mapping'] as String;
        if (mappingStr.isNotEmpty) {
          rawMaterialMapping = jsonDecode(mappingStr);
          debugPrint('📋 Local product ${product['item_name']}: ${rawMaterialMapping.length} raw materials mapped');
        }
      } catch (e) {
        debugPrint('❌ Error parsing raw_material_mapping for ${product['item_name']}: $e');
      }
    } else {
      debugPrint('⚠️ No raw_material_mapping found for ${product['item_name']}');
    }
    
    return {
      'item_name': product['item_name'],
      'org_id': product['org_id'],
      'raw_material_mapping': rawMaterialMapping,
    };
  }

  /// Reduce stock for a specific raw material with unit conversion (offline-first)
  Future<void> _reduceRawMaterialStock({
    required String storeId,
    required String materialId,
    required String materialName,
    required String materialCode,
    required double reductionQuantity,
    required String mappingUnit,
    required String salesOrderId,
    String? userId,
  }) async {
    // Ensure tables exist before proceeding
    await _localDb.ensureRawMaterialTablesExist();
    
    // Get current stock level from local DB first
    final stockData = await _localDb.getRawMaterialStock(storeId, materialId);
    
    if (stockData == null) {
      debugPrint('⚠️ No stock record found for material: $materialName');
      // Create a default stock record with 0 quantity
      await _localDb.updateRawMaterialStock(
        storeId: storeId,
        materialId: materialId,
        materialName: materialName,
        materialCode: materialCode,
        currentStock: 0,
        unit: mappingUnit,
      );
      return;
    }

    final currentQty = (stockData['current_stock'] as num?)?.toDouble() ?? 0;
    final stockUnit = stockData['unit'] as String? ?? 'PCS';

    // Convert mapping quantity to stock unit if needed
    double convertedReductionQty = reductionQuantity;
    
    if (mappingUnit.toUpperCase() != stockUnit.toUpperCase()) {
      final converted = UnitConversionService.convertQuantity(
        quantity: reductionQuantity,
        fromUnit: mappingUnit,
        toUnit: stockUnit,
      );
      
      if (converted == null) {
        debugPrint('❌ Cannot convert $mappingUnit to $stockUnit for $materialName');
        debugPrint('⚠️ Using original quantity without conversion');
      } else {
        convertedReductionQty = converted;
        debugPrint('🔄 Unit conversion: ${UnitConversionService.formatQuantity(reductionQuantity, mappingUnit)} $mappingUnit = ${UnitConversionService.formatQuantity(convertedReductionQty, stockUnit)} $stockUnit');
      }
    }

    if (currentQty < convertedReductionQty) {
      debugPrint('⚠️ Insufficient stock for $materialName: Available=${UnitConversionService.formatQuantity(currentQty, stockUnit)} $stockUnit, Required=${UnitConversionService.formatQuantity(convertedReductionQty, stockUnit)} $stockUnit');
    }

    final newCurrentQty = currentQty - convertedReductionQty;

    // Update stock levels in local DB
    await _localDb.updateRawMaterialStock(
      storeId: storeId,
      materialId: materialId,
      materialName: materialName,
      materialCode: materialCode,
      currentStock: newCurrentQty,
      unit: stockUnit,
    );

    // Record stock movement in local DB
    await _recordStockMovement(
      storeId: storeId,
      materialId: materialId,
      movementType: 'consumption',
      referenceType: 'sales_order',
      referenceId: salesOrderId,
      quantityBefore: currentQty,
      quantityChange: -convertedReductionQty,
      quantityAfter: newCurrentQty,
      remarks: 'Stock consumed for finished product sale (${UnitConversionService.formatQuantity(reductionQuantity, mappingUnit)} $mappingUnit converted to ${UnitConversionService.formatQuantity(convertedReductionQty, stockUnit)} $stockUnit) - Unit: $stockUnit',
      userId: userId,
    );

    debugPrint('📉 Stock reduced: $materialName by ${UnitConversionService.formatQuantity(convertedReductionQty, stockUnit)} $stockUnit (New: ${UnitConversionService.formatQuantity(newCurrentQty, stockUnit)} $stockUnit)');
  }

  /// Record stock movement for audit trail (offline-first)
  Future<void> _recordStockMovement({
    required String storeId,
    required String materialId,
    required String movementType,
    required String referenceType,
    required String referenceId,
    required double quantityBefore,
    required double quantityChange,
    required double quantityAfter,
    String? remarks,
    String? userId,
  }) async {
    try {
      final movementId = const Uuid().v4();
      
      // Save to local DB first
      await _localDb.recordStockMovement(
        id: movementId,
        storeId: storeId,
        productId: materialId,
        movementType: movementType,
        referenceType: referenceType,
        referenceId: referenceId,
        quantityBefore: quantityBefore,
        quantityChange: quantityChange,
        quantityAfter: quantityAfter,
        remarks: remarks,
        createdBy: userId,
      );

      // Try to sync to cloud if online
      final isOnline = await _isOnline();
      if (isOnline) {
        try {
          await _supabase.from('stock_movements').insert({
            'id': movementId,
            'store_id': storeId,
            'product_id': materialId,
            'movement_type': movementType,
            'reference_type': referenceType,
            'reference_id': referenceId,
            'quantity_before': quantityBefore,
            'quantity_change': quantityChange,
            'quantity_after': quantityAfter,
            'remarks': remarks,
            'movement_date': DateTime.now().toIso8601String(),
            'created_by': userId,
            'created_at': DateTime.now().toIso8601String(),
          });
          
          // Mark as synced
          await _localDb.markStockMovementSynced(movementId);
          debugPrint('✅ Stock movement synced to cloud');
        } catch (e) {
          debugPrint('⚠️ Stock movement saved locally, will sync later: $e');
        }
      } else {
        debugPrint('📴 Offline: Stock movement saved locally, will sync when online');
      }
    } catch (e) {
      debugPrint('❌ Stock movement recording error: $e');
    }
  }

  /// Check if sufficient raw materials are available for a sale (offline-first)
  Future<Map<String, dynamic>> checkStockAvailability({
    required String storeId,
    required String productId,
    required double requestedQuantity,
  }) async {
    try {
      // Get product with raw material mapping (offline-first)
      Map<String, dynamic>? productData;
      final isOnline = await _isOnline();
      
      if (isOnline) {
        try {
          final productResponse = await _supabase
              .from('items')
              .select('raw_material_mapping, item_name, org_id')
              .eq('id', productId)
              .eq('org_id', storeId)
              .eq('is_active', true)
              .single();
          productData = productResponse;
        } catch (e) {
          debugPrint('⚠️ Failed to get product from cloud, using local data: $e');
        }
      }
      
      // Fallback to local product data
      if (productData == null) {
        productData = await _getLocalProductData(productId);
        if (productData == null) {
          return {
            'available': false,
            'message': 'Product not found',
            'shortages': <Map<String, dynamic>>[],
          };
        }
      }

      final rawMaterialMapping = productData['raw_material_mapping'] as List?;
      if (rawMaterialMapping == null || rawMaterialMapping.isEmpty) {
        return {
          'available': true,
          'message': 'No raw material mapping required',
          'shortages': <Map<String, dynamic>>[],
        };
      }

      final shortages = <Map<String, dynamic>>[];

      // Check each raw material requirement with unit conversion
      for (final mappingData in rawMaterialMapping) {
        final mapping = RawMaterialMapping.fromJson(mappingData);
        final requiredQuantity = mapping.quantity * requestedQuantity;

        // Get stock from local DB
        final stockData = await _localDb.getRawMaterialStock(storeId, mapping.materialId);
        final availableQty = (stockData?['current_stock'] as num?)?.toDouble() ?? 0;
        final stockUnit = stockData?['unit'] as String? ?? 'PCS';

        // Convert required quantity to stock unit for comparison
        double convertedRequiredQty = requiredQuantity;
        if (mapping.uom.toUpperCase() != stockUnit.toUpperCase()) {
          final converted = UnitConversionService.convertQuantity(
            quantity: requiredQuantity,
            fromUnit: mapping.uom,
            toUnit: stockUnit,
          );
          if (converted != null) {
            convertedRequiredQty = converted;
          }
        }

        if (availableQty < convertedRequiredQty) {
          shortages.add({
            'material_name': mapping.materialName,
            'material_code': mapping.materialCode,
            'required': requiredQuantity,
            'required_unit': mapping.uom,
            'required_converted': convertedRequiredQty,
            'available': availableQty,
            'stock_unit': stockUnit,
            'shortage': convertedRequiredQty - availableQty,
            'shortage_unit': stockUnit,
          });
        }
      }

      return {
        'available': shortages.isEmpty,
        'message': shortages.isEmpty 
            ? 'All raw materials available'
            : 'Insufficient raw materials: ${shortages.map((s) => s['material_name']).join(', ')}',
        'shortages': shortages,
      };
    } catch (e) {
      debugPrint('❌ Stock availability check error: $e');
      return {
        'available': false,
        'message': 'Error checking stock availability: $e',
        'shortages': <Map<String, dynamic>>[],
      };
    }
  }

  /// Sync pending stock movements to cloud
  Future<void> syncStockMovements() async {
    try {
      final isOnline = await _isOnline();
      if (!isOnline) return;

      final unsyncedMovements = await _localDb.getUnsyncedStockMovements();
      if (unsyncedMovements.isEmpty) return;

      debugPrint('🔄 Syncing ${unsyncedMovements.length} stock movements...');

      for (final movement in unsyncedMovements) {
        try {
          await _supabase.from('stock_movements').insert({
            'id': movement['id'],
            'store_id': movement['store_id'],
            'product_id': movement['product_id'],
            'movement_type': movement['movement_type'],
            'reference_type': movement['reference_type'],
            'reference_id': movement['reference_id'],
            'quantity_before': movement['quantity_before'],
            'quantity_change': movement['quantity_change'],
            'quantity_after': movement['quantity_after'],
            'remarks': movement['remarks'],
            'movement_date': movement['movement_date'],
            'created_by': movement['created_by'],
            'created_at': movement['created_at'],
          });

          await _localDb.markStockMovementSynced(movement['id']);
          debugPrint('✅ Synced movement: ${movement['id']}');
        } catch (e) {
          debugPrint('❌ Failed to sync movement ${movement['id']}: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Stock movements sync error: $e');
    }
  }

  /// Sync raw material stock status to cloud
  Future<void> syncRawMaterialStock() async {
    try {
      final isOnline = await _isOnline();
      if (!isOnline) return;

      final unsyncedStock = await _localDb.getUnsyncedRawMaterialStock();
      if (unsyncedStock.isEmpty) return;

      debugPrint('🔄 Syncing ${unsyncedStock.length} raw material stock updates...');

      for (final stock in unsyncedStock) {
        try {
          // Use upsert with onConflict to handle existing records
          await _supabase.from('raw_material_stock_status').upsert({
            'store_id': stock['store_id'],
            'grn_item_id': stock['grn_item_id'],
            'current_stock': stock['current_stock'],
            'unit': stock['unit'] ?? 'PCS', // Required field in cloud
            'last_updated': stock['last_updated'],
            'updated_at': stock['updated_at'],
          }, onConflict: 'store_id,grn_item_id'); // Handle unique constraint

          await _localDb.markRawMaterialStockSynced(
            stock['store_id'],
            stock['grn_item_id'],
          );
          debugPrint('✅ Synced stock: ${stock['material_name'] ?? 'Unknown Material'}');
        } catch (e) {
          debugPrint('❌ Failed to sync stock ${stock['material_name'] ?? 'Unknown Material'}: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Raw material stock sync error: $e');
    }
  }
}