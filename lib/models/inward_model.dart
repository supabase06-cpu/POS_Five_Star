/// Supplier model
class Supplier {
  final String id;
  final String orgId;
  final String supplierCode;
  final String supplierName;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? gstNumber;
  final String? panNumber;
  final double creditLimit;
  final double currentBalance;
  final bool isActive;

  Supplier({
    required this.id,
    required this.orgId,
    required this.supplierCode,
    required this.supplierName,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.gstNumber,
    this.panNumber,
    this.creditLimit = 0,
    this.currentBalance = 0,
    this.isActive = true,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'],
      orgId: map['org_id'],
      supplierCode: map['supplier_code'] ?? '',
      supplierName: map['supplier_name'],
      contactPerson: map['contact_person'],
      phone: map['phone'],
      email: map['email'],
      address: map['address'],
      city: map['city'],
      state: map['state'],
      postalCode: map['postal_code'],
      gstNumber: map['gst_number'],
      panNumber: map['pan_number'],
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0,
      currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0,
      isActive: map['is_active'] ?? true,
    );
  }
}

/// Product for inward selection (from grn_master_items)
class InwardProduct {
  final String id;
  final String orgId;
  final String productCode;
  final String productName;
  final String? shortName;
  final String? categoryName;
  final String uom;
  final double costPrice;
  final double taxPercentage;
  final double currentStock;
  final bool isPerishable;
  final int? shelfLifeDays;

  InwardProduct({
    required this.id,
    required this.orgId,
    required this.productCode,
    required this.productName,
    this.shortName,
    this.categoryName,
    this.uom = 'PCS',
    this.costPrice = 0,
    this.taxPercentage = 5,
    this.currentStock = 0,
    this.isPerishable = false,
    this.shelfLifeDays,
  });

  /// Factory for grn_master_items table
  factory InwardProduct.fromGrnItem(Map<String, dynamic> map) {
    return InwardProduct(
      id: map['id'],
      orgId: map['org_id'],
      productCode: map['item_code'] ?? '',
      productName: map['item_name'],
      shortName: map['short_name'],
      categoryName: map['categories']?['category_name'],
      uom: map['uom'] ?? 'PCS',
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      taxPercentage: (map['tax_percentage'] as num?)?.toDouble() ?? 5,
      currentStock: (map['current_stock'] as num?)?.toDouble() ?? 0,
      isPerishable: map['is_perishable'] ?? false,
      shelfLifeDays: map['shelf_life_days'],
    );
  }

  /// Legacy factory for items table (kept for backward compatibility)
  factory InwardProduct.fromMap(Map<String, dynamic> map) {
    return InwardProduct(
      id: map['id'],
      orgId: map['org_id'],
      productCode: map['item_code'] ?? map['product_code'] ?? '',
      productName: map['item_name'] ?? map['product_name'],
      categoryName: map['item_categories']?['category_name'] ?? map['categories']?['category_name'],
      uom: map['unit'] ?? map['uom'] ?? 'PCS',
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      taxPercentage: (map['tax_rate'] ?? map['tax_percentage'] as num?)?.toDouble() ?? 5,
      currentStock: (map['current_stock'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Inward Header (GRN)
class InwardHeader {
  final String id;
  final String storeId;
  final String supplierId;
  final String? supplierName;
  final String grnNumber;
  final String? supplierInvoiceNo;
  final DateTime receivedDate;
  final DateTime? invoiceDate;
  final double subTotal;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final String status; // draft, posted, cancelled
  final String? receivedBy;
  final String? receivedByName;
  final String? remarks;
  final DateTime createdAt;
  final List<InwardItem> items;

  InwardHeader({
    required this.id,
    required this.storeId,
    required this.supplierId,
    this.supplierName,
    required this.grnNumber,
    this.supplierInvoiceNo,
    required this.receivedDate,
    this.invoiceDate,
    this.subTotal = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.status = 'draft',
    this.receivedBy,
    this.receivedByName,
    this.remarks,
    required this.createdAt,
    this.items = const [],
  });

  factory InwardHeader.fromMap(Map<String, dynamic> map, [List<InwardItem>? items]) {
    return InwardHeader(
      id: map['id'],
      storeId: map['store_id'],
      supplierId: map['supplier_id'],
      supplierName: map['suppliers']?['supplier_name'],
      grnNumber: map['grn_number'],
      supplierInvoiceNo: map['supplier_invoice_no'],
      receivedDate: DateTime.parse(map['received_date']),
      invoiceDate: map['invoice_date'] != null ? DateTime.parse(map['invoice_date']) : null,
      subTotal: (map['sub_total'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      status: map['status'] ?? 'draft',
      receivedBy: map['received_by'],
      receivedByName: map['app_users']?['full_name'],
      remarks: map['remarks'],
      createdAt: DateTime.parse(map['created_at']),
      items: items ?? [],
    );
  }
}

/// Inward Item (GRN Line)
class InwardItem {
  final String id;
  final String inwardId;
  final String productId;
  final String? productName;
  final String? productCode;
  final double quantity;
  final String uom;
  final double unitCost;
  final double discountPercentage;
  final double discountAmount;
  final double taxableAmount;
  final double cgstPercentage;
  final double cgstAmount;
  final double sgstPercentage;
  final double sgstAmount;
  final double totalCost;
  final String? batchNo;
  final DateTime? manufacturingDate;
  final DateTime? expiryDate;
  final DateTime? openDate;
  final int lineNumber;

  InwardItem({
    required this.id,
    required this.inwardId,
    required this.productId,
    this.productName,
    this.productCode,
    required this.quantity,
    this.uom = 'PCS',
    required this.unitCost,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    this.taxableAmount = 0,
    this.cgstPercentage = 0,
    this.cgstAmount = 0,
    this.sgstPercentage = 0,
    this.sgstAmount = 0,
    required this.totalCost,
    this.batchNo,
    this.manufacturingDate,
    this.expiryDate,
    this.openDate,
    this.lineNumber = 1,
  });

  factory InwardItem.fromMap(Map<String, dynamic> map) {
    return InwardItem(
      id: map['id'],
      inwardId: map['inward_id'],
      productId: map['product_id'],
      productName: map['grn_master_items']?['item_name'] ?? map['items']?['item_name'] ?? map['products']?['product_name'],
      productCode: map['grn_master_items']?['item_code'] ?? map['items']?['item_code'] ?? map['products']?['product_code'],
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      uom: map['uom'] ?? 'PCS',
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      discountPercentage: (map['discount_percentage'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      taxableAmount: (map['taxable_amount'] as num?)?.toDouble() ?? 0,
      cgstPercentage: (map['cgst_percentage'] as num?)?.toDouble() ?? 0,
      cgstAmount: (map['cgst_amount'] as num?)?.toDouble() ?? 0,
      sgstPercentage: (map['sgst_percentage'] as num?)?.toDouble() ?? 0,
      sgstAmount: (map['sgst_amount'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      batchNo: map['batch_no'],
      manufacturingDate: map['manufacturing_date'] != null ? DateTime.parse(map['manufacturing_date']) : null,
      expiryDate: map['expiry_date'] != null ? DateTime.parse(map['expiry_date']) : null,
      openDate: map['open_date'] != null ? DateTime.parse(map['open_date']) : null,
      lineNumber: map['line_number'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'inward_id': inwardId,
      'product_id': productId,
      'quantity': quantity,
      'uom': uom,
      'unit_cost': unitCost,
      'discount_percentage': discountPercentage,
      'discount_amount': discountAmount,
      'taxable_amount': taxableAmount,
      'cgst_percentage': cgstPercentage,
      'cgst_amount': cgstAmount,
      'sgst_percentage': sgstPercentage,
      'sgst_amount': sgstAmount,
      'total_cost': totalCost,
      'batch_no': batchNo,
      'manufacturing_date': manufacturingDate?.toIso8601String().split('T')[0],
      'expiry_date': expiryDate?.toIso8601String().split('T')[0],
      'open_date': openDate?.toIso8601String().split('T')[0],
      'line_number': lineNumber,
    };
  }
}

/// Cart item for inward entry
class InwardCartItem {
  final InwardProduct product;
  double quantity;
  double unitCost;
  double discountPercentage;
  String? batchNo;
  DateTime? manufacturingDate;
  DateTime? expiryDate;
  DateTime? openDate;

  InwardCartItem({
    required this.product,
    this.quantity = 1,
    double? unitCost,
    this.discountPercentage = 0,
    this.batchNo,
    this.manufacturingDate,
    this.expiryDate,
    this.openDate,
  }) : unitCost = unitCost ?? product.costPrice;

  double get taxPercentage => product.taxPercentage;
  double get cgstPercentage => taxPercentage / 2;
  double get sgstPercentage => taxPercentage / 2;
  
  double get grossAmount => quantity * unitCost;
  double get discountAmount => grossAmount * discountPercentage / 100;
  double get taxableAmount => grossAmount - discountAmount;
  double get cgstAmount => taxableAmount * cgstPercentage / 100;
  double get sgstAmount => taxableAmount * sgstPercentage / 100;
  double get taxAmount => cgstAmount + sgstAmount;
  double get totalCost => taxableAmount + taxAmount;
}
