import 'dart:convert';
import 'package:flutter/foundation.dart';

class Item {
  final String id;
  final String orgId;
  final String? categoryId;
  final String itemCode;
  final String itemName;
  final String? shortName;
  final String? description;
  final String? unit;
  final String? hsnCode;
  final double? costPrice;
  final double sellingPrice;
  final double? mrp;
  final double? taxRate;
  final bool? taxInclusive;
  final int? minStockLevel;
  final int? maxStockLevel;
  final int? reorderLevel;
  final bool? isCombo;
  final bool? isVeg;
  final bool? isAvailable;
  final String? imageUrl;
  final String? barcode;
  final int? displayOrder;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;
  final List<RawMaterialMapping>? rawMaterialMapping; // New: Raw materials with quantities
  final int? totalPiecesLimit; // New: Maximum total pieces for validation
  
  // Additional fields for UI
  final ItemCategory? category;
  final int? currentStock;
  final List<RawMaterial>? rawMaterials; // Deprecated: Use rawMaterialMapping instead

  Item({
    required this.id,
    required this.orgId,
    this.categoryId,
    required this.itemCode,
    required this.itemName,
    this.shortName,
    this.description,
    this.unit,
    this.hsnCode,
    this.costPrice,
    required this.sellingPrice,
    this.mrp,
    this.taxRate,
    this.taxInclusive,
    this.minStockLevel,
    this.maxStockLevel,
    this.reorderLevel,
    this.isCombo,
    this.isVeg,
    this.isAvailable,
    this.imageUrl,
    this.barcode,
    this.displayOrder,
    this.isActive,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
    this.rawMaterialMapping,
    this.totalPiecesLimit,
    this.category,
    this.currentStock,
    this.rawMaterials,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] ?? '',
      orgId: json['org_id'] ?? '',
      categoryId: json['category_id'],
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      shortName: json['short_name'],
      description: json['description'],
      unit: json['unit'] ?? 'PCS',
      hsnCode: json['hsn_code'],
      costPrice: json['cost_price']?.toDouble(),
      sellingPrice: (json['selling_price'] ?? 0).toDouble(),
      mrp: json['mrp']?.toDouble(),
      taxRate: json['tax_rate']?.toDouble() ?? 5.0,
      taxInclusive: json['tax_inclusive'] ?? true,
      minStockLevel: json['min_stock_level'] ?? 10,
      maxStockLevel: json['max_stock_level'] ?? 1000,
      reorderLevel: json['reorder_level'] ?? 20,
      isCombo: json['is_combo'] ?? false,
      isVeg: json['is_veg'] ?? false,
      isAvailable: json['is_available'] ?? true,
      imageUrl: json['image_url'],
      barcode: json['barcode'],
      displayOrder: json['display_order'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      createdBy: json['created_by'],
      updatedBy: json['updated_by'],
      rawMaterialMapping: _parseRawMaterialMapping(json['raw_material_mapping']),
      totalPiecesLimit: json['total_pieces_limit'],
      category: json['category'] != null ? ItemCategory.fromJson(json['category']) : null,
      currentStock: json['current_stock'] ?? 0,
      rawMaterials: json['raw_materials'] != null 
          ? (json['raw_materials'] as List).map((e) => RawMaterial.fromJson(e)).toList()
          : null,
    );
  }

  bool get isLowStock => currentStock != null && currentStock! <= (reorderLevel ?? 20);

  // Helper method to parse raw material mapping from different formats
  static List<RawMaterialMapping>? _parseRawMaterialMapping(dynamic rawMaterialData) {
    if (rawMaterialData == null) return null;
    
    try {
      List<dynamic> mappingList;
      
      if (rawMaterialData is String) {
        // Parse JSON string
        final decoded = jsonDecode(rawMaterialData);
        if (decoded is List) {
          mappingList = decoded;
        } else {
          debugPrint('❌ Raw material mapping is not a list: $decoded');
          return null;
        }
      } else if (rawMaterialData is List) {
        // Already a list
        mappingList = rawMaterialData;
      } else {
        debugPrint('❌ Unknown raw material mapping format: ${rawMaterialData.runtimeType}');
        return null;
      }
      
      return mappingList.map((e) => RawMaterialMapping.fromJson(e)).toList();
    } catch (e) {
      debugPrint('❌ Error parsing raw material mapping: $e');
      debugPrint('❌ Raw data: $rawMaterialData');
      return null;
    }
  }
}

class ItemCategory {
  final String id;
  final String orgId;
  final String categoryCode;
  final String categoryName;
  final String? description;
  final int? displayOrder;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ItemCategory({
    required this.id,
    required this.orgId,
    required this.categoryCode,
    required this.categoryName,
    this.description,
    this.displayOrder,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory ItemCategory.fromJson(Map<String, dynamic> json) {
    return ItemCategory(
      id: json['id'] ?? '',
      orgId: json['org_id'] ?? '',
      categoryCode: json['category_code'] ?? '',
      categoryName: json['category_name'] ?? '',
      description: json['description'],
      displayOrder: json['display_order'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }
}

class CartItem {
  final Item item;
  int quantity;

  CartItem({required this.item, this.quantity = 1});

  double get totalPrice => item.sellingPrice * quantity;
  
  // Tax calculation helpers
  double get taxExclusivePrice {
    if (item.taxInclusive == true && (item.taxRate ?? 0) > 0) {
      final taxRate = item.taxRate ?? 0;
      return totalPrice / (1 + (taxRate / 100));
    }
    return totalPrice;
  }
  
  double get taxAmount {
    if ((item.taxRate ?? 0) > 0) {
      if (item.taxInclusive == true) {
        // Extract tax from inclusive price
        final taxRate = item.taxRate ?? 0;
        return totalPrice - (totalPrice / (1 + (taxRate / 100)));
      } else {
        // Calculate tax on exclusive price
        final taxRate = item.taxRate ?? 0;
        return totalPrice * (taxRate / 100);
      }
    }
    return 0;
  }
}

// Raw Material model for mapping
class RawMaterial {
  final String id;
  final String itemCode;
  final String itemName;
  final String? shortName;
  final String uom;
  final double costPrice;
  final double currentStock;

  RawMaterial({
    required this.id,
    required this.itemCode,
    required this.itemName,
    this.shortName,
    this.uom = 'PCS',
    this.costPrice = 0,
    this.currentStock = 0,
  });

  factory RawMaterial.fromJson(Map<String, dynamic> json) {
    return RawMaterial(
      id: json['id'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      shortName: json['short_name'],
      uom: json['uom'] ?? 'PCS',
      costPrice: (json['cost_price'] ?? 0).toDouble(),
      currentStock: (json['current_stock'] ?? 0).toDouble(),
    );
  }
}

// Raw Material Mapping with quantities
class RawMaterialMapping {
  final String materialId;
  final String materialName;
  final String materialCode;
  final String uom;
  final double quantity;
  final double costPrice;
  final double currentStock;

  RawMaterialMapping({
    required this.materialId,
    required this.materialName,
    required this.materialCode,
    this.uom = 'PCS',
    required this.quantity,
    this.costPrice = 0,
    this.currentStock = 0,
  });

  factory RawMaterialMapping.fromJson(Map<String, dynamic> json) {
    return RawMaterialMapping(
      materialId: json['material_id'] ?? '',
      materialName: json['material_name'] ?? '',
      materialCode: json['material_code'] ?? '',
      uom: json['uom'] ?? 'PCS',
      quantity: (json['quantity'] ?? 0).toDouble(),
      costPrice: (json['cost_price'] ?? 0).toDouble(),
      currentStock: (json['current_stock'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'material_id': materialId,
      'material_name': materialName,
      'material_code': materialCode,
      'uom': uom,
      'quantity': quantity,
      'cost_price': costPrice,
      'current_stock': currentStock,
    };
  }

  // Simple cost calculation (for reference only, not used in stock management)
  double get totalCost => quantity * costPrice;
}