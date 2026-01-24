/// Write Off models for damaged/expired inventory management

class WriteOffHeader {
  final String id;
  final String storeId;
  final String? originalInwardId;
  final String writeOffNumber;
  final DateTime writeOffDate;
  final double subTotal;
  final double totalWriteOffAmount;
  final String writeOffStatus; // pending, approved, rejected
  final String writeOffReason;
  final double writeOffAmount;
  final DateTime? writeOffProcessedDate;
  final String? requestedBy;
  final String? requestedByName;
  final String? approvedBy;
  final String? approvedByName;
  final DateTime? approvedAt;
  final String? remarks;
  final DateTime createdAt;
  final List<WriteOffItem> items;

  WriteOffHeader({
    required this.id,
    required this.storeId,
    this.originalInwardId,
    required this.writeOffNumber,
    required this.writeOffDate,
    this.subTotal = 0,
    this.totalWriteOffAmount = 0,
    this.writeOffStatus = 'pending',
    this.writeOffReason = 'damaged',
    this.writeOffAmount = 0,
    this.writeOffProcessedDate,
    this.requestedBy,
    this.requestedByName,
    this.approvedBy,
    this.approvedByName,
    this.approvedAt,
    this.remarks,
    required this.createdAt,
    this.items = const [],
  });

  factory WriteOffHeader.fromMap(Map<String, dynamic> map, [List<WriteOffItem>? items]) {
    return WriteOffHeader(
      id: map['id'],
      storeId: map['store_id'],
      originalInwardId: map['original_inward_id'],
      writeOffNumber: map['write_off_number'],
      writeOffDate: DateTime.parse(map['write_off_date']),
      subTotal: (map['sub_total'] as num?)?.toDouble() ?? 0,
      totalWriteOffAmount: (map['total_write_off_amount'] as num?)?.toDouble() ?? 0,
      writeOffStatus: map['write_off_status'] ?? 'pending',
      writeOffReason: map['write_off_reason'] ?? 'damaged',
      writeOffAmount: (map['write_off_amount'] as num?)?.toDouble() ?? 0,
      writeOffProcessedDate: map['write_off_processed_date'] != null 
          ? DateTime.parse(map['write_off_processed_date']) : null,
      requestedBy: map['requested_by'],
      requestedByName: map['requested_user']?['full_name'],
      approvedBy: map['approved_by'],
      approvedByName: map['approved_user']?['full_name'],
      approvedAt: map['approved_at'] != null ? DateTime.parse(map['approved_at']) : null,
      remarks: map['remarks'],
      createdAt: DateTime.parse(map['created_at']),
      items: items ?? [],
    );
  }
}

class WriteOffItem {
  final String id;
  final String writeOffId;
  final String productId;
  final String? productName;
  final String? productCode;
  final String? originalInwardItemId;
  final double quantity;
  final double unitCost;
  final double totalAmount;
  final String? itemCondition;
  final String? remarks;
  final DateTime createdAt;

  // Additional fields for UI
  final double? availableQuantity;

  WriteOffItem({
    required this.id,
    required this.writeOffId,
    required this.productId,
    this.productName,
    this.productCode,
    this.originalInwardItemId,
    required this.quantity,
    required this.unitCost,
    required this.totalAmount,
    this.itemCondition,
    this.remarks,
    required this.createdAt,
    this.availableQuantity,
  });

  factory WriteOffItem.fromMap(Map<String, dynamic> map) {
    return WriteOffItem(
      id: map['id'],
      writeOffId: map['write_off_id'],
      productId: map['product_id'],
      productName: map['grn_master_items']?['item_name'] ?? map['product_name'],
      productCode: map['grn_master_items']?['item_code'] ?? map['product_code'],
      originalInwardItemId: map['original_inward_item_id'],
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      itemCondition: map['item_condition'],
      remarks: map['remarks'],
      createdAt: DateTime.parse(map['created_at']),
      availableQuantity: (map['available_quantity'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'write_off_id': writeOffId,
      'product_id': productId,
      'original_inward_item_id': originalInwardItemId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total_amount': totalAmount,
      'item_condition': itemCondition,
      'remarks': remarks,
    };
  }
}

// Write Off Cart Item for UI
class WriteOffCartItem {
  final String productId;
  final String productName;
  final String productCode;
  double quantity;
  double unitCost;
  String writeOffReason;
  String? remarks;
  final double availableQuantity;
  final String uom;

  WriteOffCartItem({
    required this.productId,
    required this.productName,
    required this.productCode,
    this.quantity = 1,
    this.unitCost = 0,
    this.writeOffReason = 'damaged',
    this.remarks,
    this.availableQuantity = 0,
    this.uom = 'PCS',
  });

  double get totalAmount => quantity * unitCost;
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