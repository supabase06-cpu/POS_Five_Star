import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'local_db_service.dart';
import 'stock_reduction_service.dart';

class SalesService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDbService _localDb = LocalDbService();
  final StockReductionService _stockService = StockReductionService();
  Timer? _syncTimer;
  bool _isSyncing = false;

  /// Start auto-sync timer (call on app start)
  void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => syncPendingOrders());
    // Also sync immediately
    syncPendingOrders();
  }

  /// Stop auto-sync timer
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Check if online
  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sync pending orders to Supabase
  Future<SyncResult> syncPendingOrders() async {
    if (_isSyncing) return SyncResult(synced: 0, failed: 0, pending: 0);
    
    _isSyncing = true;
    int synced = 0;
    int failed = 0;
    
    try {
      final isOnline = await _isOnline();
      if (!isOnline) {
        final pending = await _localDb.getUnsyncedOrdersCount();
        debugPrint('📴 Offline - $pending orders pending sync');
        _isSyncing = false;
        return SyncResult(synced: 0, failed: 0, pending: pending);
      }

      final pendingOrders = await _localDb.getUnsyncedSalesOrders();
      if (pendingOrders.isEmpty) {
        _isSyncing = false;
        return SyncResult(synced: 0, failed: 0, pending: 0);
      }

      debugPrint('🔄 Syncing ${pendingOrders.length} orders...');

      for (var order in pendingOrders) {
        try {
          await _syncOrderToSupabase(order);
          await _localDb.markSalesOrderSynced(order.id);
          synced++;
          debugPrint('✅ Synced: ${order.invoiceNo}');
        } catch (e) {
          failed++;
          await _localDb.markSalesOrderSyncFailed(order.id, e.toString());
          debugPrint('❌ Sync failed ${order.invoiceNo}: $e');
        }
      }

      debugPrint('🔄 Sync complete: $synced synced, $failed failed');
      
      // Also sync stock movements and raw material stock
      await _stockService.syncStockMovements();
      await _stockService.syncRawMaterialStock();
    } catch (e) {
      debugPrint('❌ Sync error: $e');
    }
    
    _isSyncing = false;
    final pending = await _localDb.getUnsyncedOrdersCount();
    return SyncResult(synced: synced, failed: failed, pending: pending);
  }

  /// Sync single order to Supabase
  Future<void> _syncOrderToSupabase(LocalSalesOrder order) async {
    String invoiceNo = order.invoiceNo;
    
    // Check if order with same invoice_no already exists
    final existing = await _supabase
        .from('sales_orders')
        .select('id')
        .eq('invoice_no', order.invoiceNo)
        .maybeSingle();
    
    if (existing != null) {
      // Invoice number conflict - generate a new one based on latest from Supabase
      debugPrint('⚠️ Invoice ${order.invoiceNo} exists, generating new number...');
      invoiceNo = await _generateNextInvoiceFromSupabase(order.storeId, order.orderDate);
      debugPrint('📝 New invoice number: $invoiceNo');
      
      // Update local DB with new invoice number
      await _localDb.updateLocalOrderInvoice(order.id, invoiceNo);
    }
    
    // Use upsert to handle potential ID conflicts
    await _supabase.from('sales_orders').upsert({
      'id': order.id,
      'store_id': order.storeId,
      'order_number': order.orderNumber,
      'invoice_no': invoiceNo,
      'order_type': order.orderType,
      'customer_name': order.customerName,
      'customer_phone': order.customerPhone,
      'order_date': order.orderDate,
      'order_time': order.orderTime,
      'order_timestamp': order.orderTimestamp,
      'sub_total': order.subTotal,
      'discount_amount': order.discountAmount,
      'discount_percentage': order.discountPercentage,
      'tax_amount': order.taxAmount,
      'cgst_amount': order.cgstAmount,
      'sgst_amount': order.sgstAmount,
      'total_amount': order.totalAmount,
      'round_off': order.roundOff,
      'final_amount': order.finalAmount,
      'payment_mode': order.paymentMode,
      'payment_status': order.paymentStatus,
      'amount_paid': order.amountPaid,
      'order_status': order.orderStatus,
      'fulfillment_status': 'ready',
      'billed_by': order.billedBy,
      'cashier_name': order.cashierName,
      'table_number': order.tableNumber,
      'token_number': order.tokenNumber,
      'remarks': order.remarks ?? 'Offline Order',
      'is_synced': true,
      'synced_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id'); // Handle primary key conflicts

    // Insert order items (delete existing first to handle updates)
    try {
      // Delete existing items for this order (in case of re-sync)
      await _supabase
          .from('sales_order_items')
          .delete()
          .eq('sales_order_id', order.id);
    } catch (e) {
      // Ignore if no existing items
    }

    // Insert order items
    for (var item in order.items) {
      await _supabase.from('sales_order_items').insert({
        'id': item.id,
        'sales_order_id': order.id,
        'product_id': item.productId,
        'product_name': item.productName,
        'product_code': item.productCode,
        'quantity': item.quantity,
        'uom': item.uom,
        'unit_price': item.unitPrice,
        'discount_percentage': item.discountPercentage,
        'discount_amount': item.discountAmount,
        'taxable_amount': item.taxableAmount,
        'tax_percentage': item.taxPercentage,
        'tax_amount': item.taxAmount,
        'total_line_amount': item.totalLineAmount,
        'preparation_status': 'ready',
        'line_number': item.lineNumber,
      });
    }
  }

  /// Generate next invoice number from Supabase
  Future<String> _generateNextInvoiceFromSupabase(String storeId, String orderDate) async {
    final date = DateTime.parse(orderDate);
    final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    
    // Get count of orders for this date from Supabase
    final result = await _supabase
        .from('sales_orders')
        .select('id')
        .eq('store_id', storeId)
        .eq('order_date', orderDate)
        .count();
    
    final count = (result.count ?? 0) + 1;
    return 'INV-$dateStr-${count.toString().padLeft(4, '0')}';
  }

  /// Get today's orders summary
  Future<TodayOrdersSummary> getTodayOrdersSummary(String storeId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final response = await _supabase
          .from('sales_orders')
          .select('id, invoice_no, customer_name, customer_phone, final_amount, payment_mode, order_time, order_timestamp')
          .eq('store_id', storeId)
          .eq('order_date', today)
          .order('order_timestamp', ascending: false);

      final orders = List<Map<String, dynamic>>.from(response);
      
      double totalSales = 0;
      double cashSales = 0;
      double upiSales = 0;
      double cardSales = 0;
      
      for (var order in orders) {
        final amount = (order['final_amount'] as num?)?.toDouble() ?? 0;
        totalSales += amount;
        
        final paymentMode = (order['payment_mode'] as String?)?.toLowerCase() ?? '';
        if (paymentMode == 'cash') {
          cashSales += amount;
        } else if (paymentMode == 'upi') {
          upiSales += amount;
        } else if (paymentMode == 'card') {
          cardSales += amount;
        }
      }

      return TodayOrdersSummary(
        totalOrders: orders.length,
        totalSales: totalSales,
        cashSales: cashSales,
        upiSales: upiSales,
        cardSales: cardSales,
        orders: orders,
      );
    } catch (e) {
      debugPrint('❌ Today orders error: $e');
      return TodayOrdersSummary(
        totalOrders: 0,
        totalSales: 0,
        cashSales: 0,
        upiSales: 0,
        cardSales: 0,
        orders: [],
      );
    }
  }

  /// Get orders by date range (up to 30 days) - supports offline mode
  Future<OrdersSummary> getOrdersByDateRange(String storeId, DateTime fromDate, DateTime toDate) async {
    final fromStr = fromDate.toIso8601String().split('T')[0];
    final toStr = toDate.toIso8601String().split('T')[0];
    
    debugPrint('📊 Fetching orders: $fromStr to $toStr');
    
    // Check if online
    final online = await _isOnline();
    
    if (!online) {
      debugPrint('📴 Offline - loading orders from local DB');
      return await _getLocalOrdersByDateRange(storeId, fromDate, toDate);
    }
    
    try {
      final response = await _supabase
          .from('sales_orders')
          .select('id, invoice_no, customer_name, customer_phone, final_amount, payment_mode, order_date, order_time, order_timestamp, cashier_name, billed_by')
          .eq('store_id', storeId)
          .gte('order_date', fromStr)
          .lte('order_date', toStr)
          .order('order_timestamp', ascending: false);

      final orders = List<Map<String, dynamic>>.from(response);
      
      // Also get local unsynced orders for this date range
      final localOrders = await _localDb.getLocalOrdersByDateRange(storeId, fromDate, toDate);
      final unsyncedOrders = localOrders.where((o) => !o.isSynced).toList();
      
      // Merge unsynced local orders with cloud orders
      for (var localOrder in unsyncedOrders) {
        // Check if this order is already in cloud orders (by invoice_no)
        final exists = orders.any((o) => o['invoice_no'] == localOrder.invoiceNo);
        if (!exists) {
          orders.insert(0, {
            'id': localOrder.id,
            'invoice_no': localOrder.invoiceNo,
            'customer_name': localOrder.customerName ?? 'Walk-in',
            'customer_phone': localOrder.customerPhone,
            'final_amount': localOrder.finalAmount,
            'payment_mode': localOrder.paymentMode,
            'order_date': localOrder.orderDate,
            'order_time': localOrder.orderTime,
            'order_timestamp': localOrder.orderTimestamp,
            'cashier_name': localOrder.cashierName,
            'billed_by': localOrder.billedBy,
            'is_local': true, // Mark as local/unsynced
          });
        }
      }
      
      // Sort by timestamp descending
      orders.sort((a, b) {
        final aTime = a['order_timestamp'] as String? ?? '';
        final bTime = b['order_timestamp'] as String? ?? '';
        return bTime.compareTo(aTime);
      });
      
      double totalSales = 0;
      double cashSales = 0;
      double upiSales = 0;
      double cardSales = 0;
      
      for (var order in orders) {
        final amount = (order['final_amount'] as num?)?.toDouble() ?? 0;
        totalSales += amount;
        
        final paymentMode = (order['payment_mode'] as String?)?.toLowerCase() ?? '';
        if (paymentMode == 'cash') {
          cashSales += amount;
        } else if (paymentMode == 'upi') {
          upiSales += amount;
        } else if (paymentMode == 'card') {
          cardSales += amount;
        }
      }

      debugPrint('✅ Orders fetched: ${orders.length} (${unsyncedOrders.length} local)');

      return OrdersSummary(
        totalOrders: orders.length,
        totalSales: totalSales,
        cashSales: cashSales,
        upiSales: upiSales,
        cardSales: cardSales,
        orders: orders,
      );
    } catch (e) {
      debugPrint('❌ Orders fetch error: $e');
      debugPrint('📴 Falling back to local orders');
      return await _getLocalOrdersByDateRange(storeId, fromDate, toDate);
    }
  }

  /// Get orders from local DB only (for offline mode)
  Future<OrdersSummary> _getLocalOrdersByDateRange(String storeId, DateTime fromDate, DateTime toDate) async {
    try {
      final localOrders = await _localDb.getLocalOrdersByDateRange(storeId, fromDate, toDate);
      
      final orders = localOrders.map((o) => {
        'id': o.id,
        'invoice_no': o.invoiceNo,
        'customer_name': o.customerName ?? 'Walk-in',
        'customer_phone': o.customerPhone,
        'final_amount': o.finalAmount,
        'payment_mode': o.paymentMode,
        'order_date': o.orderDate,
        'order_time': o.orderTime,
        'order_timestamp': o.orderTimestamp,
        'cashier_name': o.cashierName,
        'billed_by': o.billedBy,
        'is_local': !o.isSynced,
      }).toList();
      
      double totalSales = 0;
      double cashSales = 0;
      double upiSales = 0;
      double cardSales = 0;
      
      for (var order in orders) {
        final amount = (order['final_amount'] as num?)?.toDouble() ?? 0;
        totalSales += amount;
        
        final paymentMode = (order['payment_mode'] as String?)?.toLowerCase() ?? '';
        if (paymentMode == 'cash') {
          cashSales += amount;
        } else if (paymentMode == 'upi') {
          upiSales += amount;
        } else if (paymentMode == 'card') {
          cardSales += amount;
        }
      }

      debugPrint('📦 Local orders: ${orders.length}');

      return OrdersSummary(
        totalOrders: orders.length,
        totalSales: totalSales,
        cashSales: cashSales,
        upiSales: upiSales,
        cardSales: cardSales,
        orders: orders,
      );
    } catch (e) {
      debugPrint('❌ Local orders error: $e');
      return OrdersSummary(
        totalOrders: 0,
        totalSales: 0,
        cashSales: 0,
        upiSales: 0,
        cardSales: 0,
        orders: [],
      );
    }
  }

  /// Get order details with items - supports offline mode
  Future<Map<String, dynamic>?> getOrderDetails(String orderId) async {
    // First try to get from local DB
    final localOrder = await _localDb.getLocalOrderById(orderId);
    
    if (localOrder != null) {
      // Return local order details
      return {
        'order': {
          'id': localOrder.id,
          'invoice_no': localOrder.invoiceNo,
          'customer_name': localOrder.customerName ?? 'Walk-in',
          'customer_phone': localOrder.customerPhone,
          'order_date': localOrder.orderDate,
          'order_time': localOrder.orderTime,
          'sub_total': localOrder.subTotal,
          'cgst_amount': localOrder.cgstAmount,
          'sgst_amount': localOrder.sgstAmount,
          'final_amount': localOrder.finalAmount,
          'payment_mode': localOrder.paymentMode,
          'cashier_name': localOrder.cashierName,
          'billed_by': localOrder.billedBy,
          'is_local': !localOrder.isSynced,
        },
        'items': localOrder.items.map((item) => {
          'product_name': item.productName,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total_line_amount': item.totalLineAmount,
        }).toList(),
      };
    }
    
    // Check if online
    final online = await _isOnline();
    if (!online) {
      debugPrint('📴 Offline - order details not available');
      return null;
    }
    
    try {
      final orderResponse = await _supabase
          .from('sales_orders')
          .select()
          .eq('id', orderId)
          .single();

      final itemsResponse = await _supabase
          .from('sales_order_items')
          .select()
          .eq('sales_order_id', orderId)
          .order('line_number');

      return {
        'order': orderResponse,
        'items': List<Map<String, dynamic>>.from(itemsResponse),
      };
    } catch (e) {
      debugPrint('❌ Order details error: $e');
      return null;
    }
  }

  /// Generate invoice number: STORE-YYYYMMDD-XXXX
  Future<String> generateInvoiceNumber(String storeId) async {
    final today = DateTime.now();
    final dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    
    try {
      // Get today's order count for this store
      final result = await _supabase
          .from('sales_orders')
          .select('id')
          .eq('store_id', storeId)
          .gte('order_date', today.toIso8601String().split('T')[0])
          .count();
      
      final count = (result.count ?? 0) + 1;
      return 'INV-$dateStr-${count.toString().padLeft(4, '0')}';
    } catch (e) {
      // Fallback with timestamp
      return 'INV-$dateStr-${DateTime.now().millisecondsSinceEpoch % 10000}';
    }
  }

  /// Generate order number
  String generateOrderNumber() {
    final now = DateTime.now();
    return 'ORD-${now.millisecondsSinceEpoch}';
  }

  /// Create a sales order - saves locally first, then syncs to Supabase
  Future<SalesOrderResult?> createSalesOrder(SalesOrderData orderData) async {
    try {
      final orderId = const Uuid().v4();
      final invoiceNo = await _localDb.generateLocalInvoiceNumber(orderData.storeId);
      final orderNumber = generateOrderNumber();
      final now = DateTime.now();

      debugPrint('📝 Creating sales order (offline-first)...');
      debugPrint('   Store: ${orderData.storeId}');
      debugPrint('   Customer: ${orderData.customerName ?? "Walk-in"}');
      debugPrint('   Items: ${orderData.items.length}');
      debugPrint('   Total: ₹${orderData.finalAmount}');

      // Create local order
      int lineNumber = 1;
      final localOrder = LocalSalesOrder(
        id: orderId,
        storeId: orderData.storeId,
        orderNumber: orderNumber,
        invoiceNo: invoiceNo,
        orderType: orderData.orderType,
        customerName: orderData.customerName,
        customerPhone: orderData.customerPhone,
        orderDate: now.toIso8601String().split('T')[0],
        orderTime: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
        orderTimestamp: now.toIso8601String(),
        subTotal: orderData.subTotal,
        discountAmount: orderData.discountAmount,
        discountPercentage: orderData.discountPercentage,
        taxAmount: orderData.taxAmount,
        cgstAmount: orderData.cgstAmount,
        sgstAmount: orderData.sgstAmount,
        totalAmount: orderData.totalAmount,
        roundOff: orderData.roundOff,
        finalAmount: orderData.finalAmount,
        paymentMode: orderData.paymentMode,
        paymentStatus: 'paid',
        amountPaid: orderData.finalAmount,
        orderStatus: 'completed',
        billedBy: orderData.billedBy,
        cashierName: orderData.cashierName,
        tableNumber: orderData.tableNumber,
        tokenNumber: orderData.tokenNumber,
        remarks: orderData.remarks,
        createdAt: now,
        items: orderData.items.map((item) => LocalSalesOrderItem(
          id: const Uuid().v4(),
          salesOrderId: orderId,
          productId: item.productId,
          productName: item.productName,
          productCode: item.productCode,
          quantity: item.quantity,
          uom: item.uom,
          unitPrice: item.unitPrice,
          discountPercentage: item.discountPercentage,
          discountAmount: item.discountAmount,
          taxableAmount: item.taxableAmount,
          taxPercentage: item.taxPercentage,
          taxAmount: item.taxAmount,
          totalLineAmount: item.totalLineAmount,
          lineNumber: lineNumber++,
        )).toList(),
      );

      // Save to local SQLite first (works offline)
      await _localDb.saveLocalSalesOrder(localOrder);
      debugPrint('✅ Order saved locally: $invoiceNo');

      // Try to sync immediately if online
      final isOnline = await _isOnline();
      if (isOnline) {
        try {
          await _syncOrderToSupabase(localOrder);
          await _localDb.markSalesOrderSynced(orderId);
          debugPrint('✅ Order synced to cloud: $invoiceNo');
        } catch (e) {
          debugPrint('⚠️ Cloud sync pending: $e');
          // Order is saved locally, will sync later
        }
      } else {
        debugPrint('📴 Offline - order will sync when online');
      }

      return SalesOrderResult(orderId: orderId, invoiceNo: invoiceNo);
    } catch (e) {
      debugPrint('❌ Sales order error: $e');
      return null;
    }
  }

  /// Get pending sync count
  Future<int> getPendingSyncCount() async {
    return await _localDb.getUnsyncedOrdersCount();
  }
}

class SyncResult {
  final int synced;
  final int failed;
  final int pending;

  SyncResult({required this.synced, required this.failed, required this.pending});
}

class SalesOrderResult {
  final String orderId;
  final String invoiceNo;

  SalesOrderResult({required this.orderId, required this.invoiceNo});
}

class SalesOrderData {
  final String storeId;
  final String orderType;
  final String? customerName;
  final String? customerPhone;
  final double subTotal;
  final double discountAmount;
  final double discountPercentage;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double totalAmount;
  final double roundOff;
  final double finalAmount;
  final String paymentMode;
  final String billedBy;
  final String? cashierName;
  final String? tableNumber;
  final String? tokenNumber;
  final String? remarks;
  final List<SalesOrderItemData> items;

  SalesOrderData({
    required this.storeId,
    this.orderType = 'dine_in',
    this.customerName,
    this.customerPhone,
    required this.subTotal,
    this.discountAmount = 0,
    this.discountPercentage = 0,
    required this.taxAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.totalAmount,
    this.roundOff = 0,
    required this.finalAmount,
    required this.paymentMode,
    required this.billedBy,
    this.cashierName,
    this.tableNumber,
    this.tokenNumber,
    this.remarks,
    required this.items,
  });
}

class SalesOrderItemData {
  final String productId;
  final String productName;
  final String? productCode;
  final double quantity;
  final String uom;
  final double unitPrice;
  final double discountPercentage;
  final double discountAmount;
  final double taxableAmount;
  final double taxPercentage;
  final double taxAmount;
  final double totalLineAmount;

  SalesOrderItemData({
    required this.productId,
    required this.productName,
    this.productCode,
    required this.quantity,
    this.uom = 'PCS',
    required this.unitPrice,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    required this.taxableAmount,
    this.taxPercentage = 5,
    this.taxAmount = 0,
    required this.totalLineAmount,
  });
}


class TodayOrdersSummary {
  final int totalOrders;
  final double totalSales;
  final double cashSales;
  final double upiSales;
  final double cardSales;
  final List<Map<String, dynamic>> orders;

  TodayOrdersSummary({
    required this.totalOrders,
    required this.totalSales,
    required this.cashSales,
    required this.upiSales,
    required this.cardSales,
    required this.orders,
  });
}

class OrdersSummary {
  final int totalOrders;
  final double totalSales;
  final double cashSales;
  final double upiSales;
  final double cardSales;
  final List<Map<String, dynamic>> orders;

  OrdersSummary({
    required this.totalOrders,
    required this.totalSales,
    required this.cashSales,
    required this.upiSales,
    required this.cardSales,
    required this.orders,
  });
}
