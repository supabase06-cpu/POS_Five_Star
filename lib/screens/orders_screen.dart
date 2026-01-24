import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/sales_service.dart';
import '../services/invoice_printer_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final SalesService _salesService = SalesService();
  final InvoicePrinterService _invoicePrinterService = InvoicePrinterService();
  
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String? _storeId;
  
  bool _isLoading = true;
  OrdersSummary? _summary;
  int _pendingSyncCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _storeId = authProvider.userProfile?.organizationId;
    
    if (_storeId != null) {
      await _loadOrders();
      await _loadPendingSyncCount();
    }
  }

  Future<void> _loadPendingSyncCount() async {
    final count = await _salesService.getPendingSyncCount();
    setState(() => _pendingSyncCount = count);
  }

  Future<void> _syncNow() async {
    setState(() => _isLoading = true);
    final result = await _salesService.syncPendingOrders();
    await _loadOrders();
    await _loadPendingSyncCount();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.synced > 0 
            ? '✅ Synced ${result.synced} orders' 
            : result.pending > 0 
              ? '📴 Offline - ${result.pending} orders pending'
              : 'All orders synced'),
          backgroundColor: result.synced > 0 ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _printOrder(String orderId) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Get order details
      final details = await _salesService.getOrderDetails(orderId);
      if (details == null) {
        Navigator.pop(context); // Close loading dialog
        _showErrorSnackBar('Failed to load order details');
        return;
      }

      final order = details['order'] as Map<String, dynamic>;
      final items = details['items'] as List<Map<String, dynamic>>;
      final billedBy = _getBilledByName(order);

      // Create InvoiceData object
      final invoiceData = InvoiceData(
        invoiceNumber: order['invoice_no'] ?? 'N/A',
        date: _formatDateFromString(order['order_date'] ?? ''),
        time: _formatTime(order['order_time'] ?? ''),
        cashierName: billedBy,
        customerName: order['customer_name'] ?? 'Walk-in Customer',
        storeName: 'Five Star Chicken',
        storeAddress: '',
        storePhone: '',
        items: items.map((item) => InvoiceItem(
          name: item['product_name'] ?? '',
          quantity: (item['quantity'] as num?)?.toInt() ?? 0,
          price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          total: (item['total_line_amount'] as num?)?.toDouble() ?? 0.0,
        )).toList(),
        subtotal: (order['sub_total'] as num?)?.toDouble() ?? 0.0,
        discount: 0.0,
        tax: ((order['cgst_amount'] as num?)?.toDouble() ?? 0.0) + 
             ((order['sgst_amount'] as num?)?.toDouble() ?? 0.0),
        total: (order['final_amount'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: order['payment_mode'] ?? 'cash',
        amountPaid: (order['final_amount'] as num?)?.toDouble() ?? 0.0,
        change: 0.0,
        qrData: 'INV-${order['invoice_no'] ?? ''}',
      );

      Navigator.pop(context); // Close loading dialog

      // Print the invoice
      final success = await _invoicePrinterService.printInvoice(invoiceData);
      
      if (success) {
        _showSuccessSnackBar('Invoice printed successfully!');
      } else {
        _showErrorSnackBar('Failed to print invoice. Please check printer connection.');
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog if still open
      _showErrorSnackBar('Error printing invoice: ${e.toString()}');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _loadOrders() async {
    if (_storeId == null) return;
    
    setState(() => _isLoading = true);
    
    final summary = await _salesService.getOrdersByDateRange(
      _storeId!,
      _fromDate,
      _toDate,
    );
    
    setState(() {
      _summary = summary;
      _isLoading = false;
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      helpText: 'Select Date Range',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      saveText: 'Apply',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.orange[600]!,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: Dialog(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: child,
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      await _loadOrders();
    }
  }

  void _setQuickFilter(int days) {
    setState(() {
      _toDate = DateTime.now();
      _fromDate = DateTime.now().subtract(Duration(days: days));
    });
    _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          _buildSummaryCards(),
          Expanded(child: _buildOrdersList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      color: Colors.orange[600],
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Orders',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          // Sync Status Button
          if (_pendingSyncCount > 0)
            InkWell(
              onTap: _syncNow,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red[400],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$_pendingSyncCount Pending',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[400],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Synced',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const DebugButton(),
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          // Quick Filters
          _buildQuickFilterChip('Today', 0),
          const SizedBox(width: 8),
          _buildQuickFilterChip('7 Days', 7),
          const SizedBox(width: 8),
          _buildQuickFilterChip('15 Days', 15),
          const SizedBox(width: 8),
          _buildQuickFilterChip('30 Days', 30),
          const SizedBox(width: 16),
          // Date Range Picker
          InkWell(
            onTap: _selectDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange[600]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 18, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatDate(_fromDate)} - ${_formatDate(_toDate)}',
                    style: TextStyle(color: Colors.orange[600], fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_drop_down, color: Colors.orange[600]),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Refresh Button
          IconButton(
            onPressed: _loadOrders,
            icon: Icon(Icons.refresh, color: Colors.grey[700]),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFilterChip(String label, int days) {
    final isSelected = _isDateRangeSelected(days);
    return InkWell(
      onTap: () => _setQuickFilter(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[600] : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  bool _isDateRangeSelected(int days) {
    final today = DateTime.now();
    final expectedFrom = today.subtract(Duration(days: days));
    return _fromDate.day == expectedFrom.day && 
           _fromDate.month == expectedFrom.month &&
           _toDate.day == today.day && 
           _toDate.month == today.month;
  }

  Widget _buildSummaryCards() {
    if (_isLoading || _summary == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: List.generate(5, (index) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index < 4 ? 12 : 0),
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildSummaryCard('Total Orders', '${_summary!.totalOrders}', Icons.shopping_bag, Colors.blue),
          const SizedBox(width: 12),
          _buildSummaryCard('Total Sales', '₹${_formatAmount(_summary!.totalSales)}', Icons.currency_rupee, Colors.green),
          const SizedBox(width: 12),
          _buildSummaryCard('Cash', '₹${_formatAmount(_summary!.cashSales)}', Icons.money, Colors.teal),
          const SizedBox(width: 12),
          _buildSummaryCard('UPI', '₹${_formatAmount(_summary!.upiSales)}', Icons.qr_code, Colors.purple),
          const SizedBox(width: 12),
          _buildSummaryCard('Card', '₹${_formatAmount(_summary!.cardSales)}', Icons.credit_card, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_summary == null || _summary!.orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No orders found', style: TextStyle(fontSize: 18, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text('Try selecting a different date range', style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                _buildTableHeader('Invoice', flex: 2),
                _buildTableHeader('Customer', flex: 2),
                _buildTableHeader('Date & Time', flex: 2),
                _buildTableHeader('Billed By', flex: 2),
                _buildTableHeader('Amount', flex: 1),
                _buildTableHeader('Payment', flex: 1),
                _buildTableHeader('Action', flex: 1),
              ],
            ),
          ),
          const Divider(height: 1),
          // Table Body
          Expanded(
            child: ListView.separated(
              itemCount: _summary!.orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = _summary!.orders[index];
                return _buildOrderRow(order);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: 13),
      ),
    );
  }

  Widget _buildOrderRow(Map<String, dynamic> order) {
    final invoiceNo = order['invoice_no'] ?? '';
    final customerName = order['customer_name'] ?? 'Walk-in';
    final amount = (order['final_amount'] as num?)?.toDouble() ?? 0;
    final paymentMode = order['payment_mode'] ?? 'cash';
    final orderDate = order['order_date'] ?? '';
    final orderTime = order['order_time'] ?? '';
    final billedBy = _getBilledByName(order);
    final isLocal = order['is_local'] == true;

    return InkWell(
      onTap: () => _showOrderDetails(order['id']),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isLocal ? Colors.orange[50] : null,
        child: Row(
          children: [
            // Invoice
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Text(invoiceNo, style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (isLocal) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange[600],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'LOCAL',
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Customer
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.orange[100],
                    child: Text(
                      customerName[0].toUpperCase(),
                      style: TextStyle(color: Colors.orange[800], fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(customerName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            // Date & Time
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatDateFromString(orderDate), style: const TextStyle(fontSize: 13)),
                  Text(_formatTime(orderTime), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            // Billed By
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(billedBy, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[700])),
                  ),
                ],
              ),
            ),
            // Amount
            Expanded(
              flex: 1,
              child: Text(
                '₹${amount.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700]),
              ),
            ),
            // Payment Mode
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getPaymentColor(paymentMode).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  paymentMode.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _getPaymentColor(paymentMode),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Action
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.visibility, color: Colors.blue[600], size: 20),
                    onPressed: () => _showOrderDetails(order['id']),
                    tooltip: 'View Details',
                  ),
                  IconButton(
                    icon: Icon(Icons.print, color: Colors.grey[600], size: 20),
                    onPressed: () => _printOrder(order['id']),
                    tooltip: 'Print',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOrderDetails(String orderId) async {
    final details = await _salesService.getOrderDetails(orderId);
    if (details == null || !mounted) return;

    final order = details['order'] as Map<String, dynamic>;
    final items = details['items'] as List<Map<String, dynamic>>;
    final billedBy = _getBilledByName(order);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt, color: Colors.orange),
            const SizedBox(width: 8),
            Text(order['invoice_no'] ?? 'Order Details'),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Customer & Time Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Customer', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            Text(order['customer_name'] ?? 'Walk-in', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (order['customer_phone'] != null)
                              Text(order['customer_phone'], style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Date & Time', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            Text(_formatDateFromString(order['order_date']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(_formatTime(order['order_time']), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Billed By Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 20, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text('Billed By: ', style: TextStyle(fontSize: 13, color: Colors.blue[700])),
                      Text(billedBy, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue[800])),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Items Header
                Row(
                  children: [
                    Expanded(flex: 3, child: Text('Item', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600))),
                    Expanded(flex: 1, child: Text('Qty', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    Expanded(flex: 1, child: Text('Price', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                    Expanded(flex: 1, child: Text('Total', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                  ],
                ),
                const Divider(),
                // Items
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(item['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500))),
                      Expanded(flex: 1, child: Text('${item['quantity']}', textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text('₹${(item['unit_price'] as num?)?.toStringAsFixed(0) ?? '0'}', textAlign: TextAlign.right)),
                      Expanded(flex: 1, child: Text('₹${(item['total_line_amount'] as num?)?.toStringAsFixed(0) ?? '0'}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w500))),
                    ],
                  ),
                )),
                const Divider(),
                // Totals
                _buildTotalRow('Subtotal', '₹${(order['sub_total'] as num?)?.toStringAsFixed(2) ?? '0'}'),
                _buildTotalRow('CGST (${_calculateTaxRate(order, 'cgst')}%)', '₹${(order['cgst_amount'] as num?)?.toStringAsFixed(2) ?? '0'}'),
                _buildTotalRow('SGST (${_calculateTaxRate(order, 'sgst')}%)', '₹${(order['sgst_amount'] as num?)?.toStringAsFixed(2) ?? '0'}'),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('₹${(order['final_amount'] as num?)?.toStringAsFixed(2) ?? '0'}', 
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green[700])),
                  ],
                ),
                const SizedBox(height: 16),
                // Payment Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_getPaymentIcon(order['payment_mode'] ?? 'cash'), color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Text('Paid via ${(order['payment_mode'] ?? 'cash').toString().toUpperCase()}', 
                          style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green[700],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('PAID', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value),
        ],
      ),
    );
  }

  String _calculateTaxRate(Map<String, dynamic> order, String taxType) {
    try {
      final subtotal = (order['sub_total'] as num?)?.toDouble() ?? 0;
      final taxAmount = taxType == 'cgst' 
          ? (order['cgst_amount'] as num?)?.toDouble() ?? 0
          : (order['sgst_amount'] as num?)?.toDouble() ?? 0;
      
      if (subtotal > 0 && taxAmount > 0) {
        final rate = (taxAmount / subtotal) * 100;
        return rate.toStringAsFixed(1);
      }
      return '0.0';
    } catch (e) {
      return '0.0';
    }
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatDateFromString(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String time) {
    if (time.isEmpty) return '';
    final parts = time.split(':');
    if (parts.length < 2) return time;
    int hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour:$minute $period';
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  Color _getPaymentColor(String mode) {
    switch (mode.toLowerCase()) {
      case 'cash': return Colors.teal;
      case 'upi': return Colors.purple;
      case 'card': return Colors.indigo;
      default: return Colors.grey;
    }
  }

  IconData _getPaymentIcon(String mode) {
    switch (mode.toLowerCase()) {
      case 'cash': return Icons.money;
      case 'upi': return Icons.qr_code;
      case 'card': return Icons.credit_card;
      default: return Icons.payment;
    }
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _getBilledByName(Map<String, dynamic> order) {
    final cashierName = order['cashier_name'] as String?;
    final billedBy = order['billed_by'] as String?;
    
    if (cashierName != null && cashierName.isNotEmpty) {
      return _capitalizeWords(cashierName);
    }
    if (billedBy != null && billedBy.isNotEmpty) {
      // If it's an email, show the part before @
      if (billedBy.contains('@')) {
        return _capitalizeWords(billedBy.split('@')[0].replaceAll('.', ' '));
      }
      return _capitalizeWords(billedBy);
    }
    return 'N/A';
  }
}
