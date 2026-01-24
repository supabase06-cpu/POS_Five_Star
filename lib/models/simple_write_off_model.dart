/// Simplified Write Off models - no vendor or batch tracking

class SimpleWriteOffHeader {
  final String id;
  final String storeId;
  final String writeOffNumber;
  final DateTime writeOffDate;
  final String writeOffReason;
  final String writeOffStatus; // pending, completed
  final String? requestedBy;
  final String? requestedByName;
  final String? remarks;
  final DateTime createdAt;
  final List<SimpleWriteOffItem> items;

  SimpleWriteOffHeader({
    required this.id,
    required this.storeId,
    required this.writeOffNumber,
    required this.writeOffDate,
    this.writeOffReason = 'damaged',
    this.writeOffStatus = 'pending',
    this.requestedBy,
    this.requestedByName,
    this.remarks,
    required this.createdAt,
    this.items = const [],
  });

  factory SimpleWriteOffHeader.fromMap(Map<String, dynamic> map, [List<SimpleWriteOffItem>? items]) {
    return SimpleWriteOffHeader(
      id: map['id'],
      storeId: map['store_id'],
      writeOffNumber: map['write_off_number'],
      writeOffDate: DateTime.parse(map['write_off_date']),
      writeOffReason: map['write_off_reason'] ?? 'damaged',
      writeOffStatus: map['write_off_status'] ?? 'pending',
      requestedBy: map['requested_by'],
      requestedByName: map['requested_user']?['full_name'],
      remarks: map['remarks'],
      createdAt: DateTime.parse(map['created_at']),
      items: items ?? [],
    );
  }
}

class SimpleWriteOffItem {
  final String id;
  final String writeOffId;
  final String productId;
  final String? productName;
  final String? productCode;
  final double quantity;
  final String uom;
  final double unitCost;
  final double totalAmount;
  final String? itemCondition; // reason for this specific item
  final String? remarks;
  final DateTime createdAt;

  SimpleWriteOffItem({
    required this.id,
    required this.writeOffId,
    required this.productId,
    this.productName,
    this.productCode,
    required this.quantity,
    this.uom = 'PCS',
    this.unitCost = 0,
    this.totalAmount = 0,
    this.itemCondition,
    this.remarks,
    required this.createdAt,
  });

  factory SimpleWriteOffItem.fromMap(Map<String, dynamic> map) {
    return SimpleWriteOffItem(
      id: map['id'],
      writeOffId: map['write_off_id'],
      productId: map['product_id'],
      productName: map['grn_master_items']?['item_name'] ?? map['product_name'],
      productCode: map['grn_master_items']?['item_code'] ?? map['product_code'],
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      uom: map['grn_master_items']?['uom'] ?? map['uom'] ?? 'PCS',
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      itemCondition: map['item_condition'],
      remarks: map['remarks'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'write_off_id': writeOffId,
      'product_id': productId,
      'quantity': quantity,
      'uom': uom,
      'unit_cost': unitCost,
      'total_amount': totalAmount,
      'item_condition': itemCondition,
      'remarks': remarks,
    };
  }
}

// Simple Write Off Cart Item for UI
class SimpleWriteOffCartItem {
  final String productId;
  final String productName;
  final String productCode;
  double quantity;
  String writeOffReason;
  String? remarks;
  final String uom;
  final double availableStock;
  final double unitCost;

  SimpleWriteOffCartItem({
    required this.productId,
    required this.productName,
    required this.productCode,
    this.quantity = 1,
    this.writeOffReason = 'damaged',
    this.remarks,
    this.uom = 'PCS',
    this.availableStock = 0,
    this.unitCost = 0,
  });
}

// Write Off Reasons
class WriteOffReason {
  static const String damaged = 'damaged';
  static const String expired = 'expired';
  static const String spoiled = 'spoiled';
  static const String contaminated = 'contaminated';
  static const String theft = 'theft';
  static const String other = 'other';

  static const Map<String, String> reasons = {
    damaged: 'Damaged',
    expired: 'Expired',
    spoiled: 'Spoiled',
    contaminated: 'Contaminated',
    theft: 'Theft/Loss',
    other: 'Other',
  };

  static List<String> get allReasons => reasons.keys.toList();
  static String getDisplayName(String reason) => reasons[reason] ?? reason;
}