import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/auth_provider.dart';
import '../models/item_model.dart';
import '../services/item_service.dart';
import '../services/product_service.dart';
import '../services/local_db_service.dart';
import '../services/customer_service.dart';
import '../services/sales_service.dart';
import '../services/stock_reduction_service.dart';
import '../services/debug_logger_service.dart';
import '../services/image_cache_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/invoice_preview_dialog.dart';
import '../widgets/offline_image.dart';
import '../widgets/cached_product_image.dart';
import '../widgets/debug_panel.dart';
import '../services/invoice_printer_service.dart';
import 'orders_screen.dart';
import 'products_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ItemService _itemService = ItemService();
  final LocalDbService _localDb = LocalDbService();
  final CustomerService _customerService = CustomerService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  final SalesService _salesService = SalesService();
  final StockReductionService _stockReductionService = StockReductionService();
  final InvoicePrinterService _invoicePrinterService = InvoicePrinterService();
  
  List<ItemCategory> _categories = [];
  List<Item> _items = [];
  List<Item> _filteredItems = [];
  List<CartItem> _cartItems = [];
  
  String? _selectedCategoryId;
  dynamic _selectedCustomer = 'Walk-in Customer (F2)';
  bool _isLoading = true;
  String? _orgId;
  String? _storeId;
  String? _userId;
  String? _userName;
  int _holdOrdersCount = 0;
  String? _activeHoldOrderId; // Track restored hold order

  @override
  void initState() {
    super.initState();
    _initializeData();
    // Start auto-sync for offline orders
    _salesService.startAutoSync();
  }

  @override
  void dispose() {
    _salesService.stopAutoSync();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _orgId = authProvider.userProfile?.organizationId;
    _storeId = authProvider.userProfile?.organizationId; // Using org_id as store_id for now
    _userId = authProvider.user?.id;
    _userName = authProvider.userProfile?.fullName;
    
    if (_orgId != null) {
      await _loadCategories();
      await _loadItems();
      await _loadHoldOrdersCount();
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadHoldOrdersCount() async {
    if (_orgId == null) return;
    final count = await _localDb.getHoldOrdersCount(_orgId!, storeId: _storeId);
    setState(() => _holdOrdersCount = count);
  }

  Future<void> _printInvoice(String invoiceNumber, String paymentMethod, String customerName) async {
    try {
      // Use the customer name passed from the order
      print('DEBUG: Customer name received for printing: "$customerName"');
      
      final invoiceData = InvoiceData(
        invoiceNumber: invoiceNumber,
        date: _formatDate(DateTime.now()),
        time: _formatTime(DateTime.now()),
        cashierName: _userName ?? 'Unknown',
        customerName: customerName.isNotEmpty ? customerName : 'Walk-in Customer',
        storeName: '', // Empty to avoid duplicate
        storeAddress: '', // You can add store address from settings
        storePhone: '', // You can add store phone from settings
        items: _cartItems.map((cartItem) => InvoiceItem(
          name: cartItem.item.itemName,
          quantity: cartItem.quantity,
          price: cartItem.item.sellingPrice,
          total: cartItem.totalPrice,
        )).toList(),
        subtotal: _getSubtotal(),
        discount: 0.0, // Add discount logic if needed
        tax: _getTaxAmount(),
        total: _getTotal(),
        paymentMethod: paymentMethod,
        amountPaid: _getTotal(),
        change: 0.0,
        qrData: 'INV-$invoiceNumber', // You can customize QR data
      );

      final success = await _invoicePrinterService.printInvoice(invoiceData);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice printed successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to print invoice. Check printer connection.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Print error: $e');
      if (mounted) {
        // Show printer error dialog with "Bill Anyway" option
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.print_disabled, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  const Text('Printer Error'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.toString().replaceFirst('Exception: ', ''),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You can still complete the order without printing. The invoice will be saved and can be reprinted later.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Open printer settings
                    Navigator.pushNamed(context, '/printer-settings');
                  },
                  child: const Text('Printer Settings'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Show success message for billing without printing
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Order completed successfully! Invoice saved (not printed).'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Bill Anyway'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  Future<void> _loadCategories() async {
    if (_orgId == null) return;
    
    final categories = await _itemService.getCategories(_orgId!);
    setState(() {
      _categories = categories;
    });
  }

  Future<void> _loadItems() async {
    if (_orgId == null) return;
    
    debugPrint('📦 BILLING: Loading items for org: $_orgId');
    debugPrint('📦 BILLING: Category filter: $_selectedCategoryId');
    debugPrint('📦 BILLING: Search query: ${_searchController.text.trim()}');
    
    final items = await _itemService.getItems(
      _orgId!,
      categoryId: _selectedCategoryId,
      searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
    );
    
    debugPrint('📦 BILLING: Loaded ${items.length} items from ItemService');
    
    // Debug: Check specific items for raw material mapping
    for (final item in items) {
      if (item.rawMaterialMapping != null && item.rawMaterialMapping!.isNotEmpty) {
        debugPrint('📦 BILLING: Item ${item.itemName} (${item.id}) has ${item.rawMaterialMapping!.length} mappings');
        for (int i = 0; i < item.rawMaterialMapping!.length; i++) {
          final mapping = item.rawMaterialMapping![i];
          debugPrint('📦 BILLING: - Mapping $i: ${mapping.materialName} ${mapping.quantity} ${mapping.uom}');
        }
      } else {
        debugPrint('📦 BILLING: Item ${item.itemName} (${item.id}) has NO mappings');
      }
    }
    
    // Get stock levels if store_id is available
    if (_storeId != null && items.isNotEmpty) {
      final itemIds = items.map((item) => item.id).toList();
      final stockLevels = await _itemService.getStockLevels(_storeId!, itemIds);
      
      // Update items with current stock
      for (var item in items) {
        final stockLevel = stockLevels[item.id] ?? 0;
        // Create new item with stock info (since Item is immutable)
        final updatedItem = Item(
          id: item.id,
          orgId: item.orgId,
          categoryId: item.categoryId,
          itemCode: item.itemCode,
          itemName: item.itemName,
          shortName: item.shortName,
          description: item.description,
          unit: item.unit,
          hsnCode: item.hsnCode,
          costPrice: item.costPrice,
          sellingPrice: item.sellingPrice,
          mrp: item.mrp,
          taxRate: item.taxRate,
          taxInclusive: item.taxInclusive,
          minStockLevel: item.minStockLevel,
          maxStockLevel: item.maxStockLevel,
          reorderLevel: item.reorderLevel,
          isCombo: item.isCombo,
          isVeg: item.isVeg,
          isAvailable: item.isAvailable,
          imageUrl: item.imageUrl,
          barcode: item.barcode,
          displayOrder: item.displayOrder,
          isActive: item.isActive,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          createdBy: item.createdBy,
          updatedBy: item.updatedBy,
          category: item.category,
          currentStock: stockLevel,
          rawMaterialMapping: item.rawMaterialMapping, // IMPORTANT: Preserve raw material mapping
          totalPiecesLimit: item.totalPiecesLimit,
        );
        
        // Replace item in list
        final index = items.indexOf(item);
        items[index] = updatedItem;
      }
    }
    
    setState(() {
      _items = items;
      _filteredItems = items;
    });
    
    debugPrint('📦 BILLING: Items state updated with ${_items.length} items');
    
    // Preload product images in background
    _preloadProductImages(items);
  }

  /// Preload product images for better performance
  Future<void> _preloadProductImages(List<Item> items) async {
    try {
      final productsWithImages = items
          .where((item) => item.imageUrl != null && item.imageUrl!.isNotEmpty)
          .map((item) => {
            'id': item.id,
            'image_url': item.imageUrl!,
          })
          .toList();

      if (productsWithImages.isNotEmpty) {
        debugPrint('📷 Preloading ${productsWithImages.length} product images...');
        await _imageCacheService.cacheProductImages(productsWithImages);
        
        // Show cache stats
        final stats = await _imageCacheService.getCacheStats();
        debugPrint('📊 Image cache: ${stats['cached_images']} images, ${stats['total_size_mb']} MB');
      }
    } catch (e) {
      debugPrint('❌ Error preloading images: $e');
      // Continue without image caching if it fails
    }
  }

  /// Get image cache statistics
  Future<Map<String, dynamic>> getImageCacheStats() async {
    return await _imageCacheService.getCacheStats();
  }

  void _onCategoryChanged(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      _isLoading = true;
    });
    _loadItems().then((_) {
      setState(() {
        _isLoading = false;
      });
    });
  }

  void _onSearchChanged() {
    setState(() {
      _isLoading = true;
    });
    _loadItems().then((_) {
      setState(() {
        _isLoading = false;
      });
    });
  }

  // Tax calculations based on individual product tax rates
  double get subtotalExcludingTax {
    return _cartItems.fold(0, (sum, cartItem) => sum + cartItem.taxExclusivePrice);
  }

  double get totalTaxAmount {
    return _cartItems.fold(0, (sum, cartItem) => sum + cartItem.taxAmount);
  }

  double get cgst => totalTaxAmount / 2; // Split tax equally between CGST and SGST
  double get sgst => totalTaxAmount / 2;
  
  // Calculate average tax rate for display purposes
  double get averageTaxRate {
    if (_cartItems.isEmpty) return 0;
    
    double totalTaxableAmount = 0;
    double totalTaxAmount = 0;
    
    for (final cartItem in _cartItems) {
      final taxRate = cartItem.item.taxRate ?? 0;
      if (taxRate > 0) {
        totalTaxableAmount += cartItem.taxExclusivePrice;
        totalTaxAmount += cartItem.taxAmount;
      }
    }
    
    if (totalTaxableAmount == 0) return 0;
    return (totalTaxAmount / totalTaxableAmount) * 100;
  }
  
  double get cgstRate => averageTaxRate / 2;
  double get sgstRate => averageTaxRate / 2;
  
  double get subtotal => subtotalExcludingTax; // Use tax-exclusive subtotal
  double get totalAmount => subtotalExcludingTax + totalTaxAmount;

  // Helper methods for invoice printing
  double _getSubtotal() => subtotal;
  double _getTaxAmount() => totalTaxAmount;
  double _getTotal() => totalAmount;

  void _addToCart(Item item) {
    setState(() {
      final existingIndex = _cartItems.indexWhere((cartItem) => cartItem.item.id == item.id);
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity++;
      } else {
        _cartItems.add(CartItem(item: item, quantity: 1));
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      _cartItems[index].quantity += delta;
      if (_cartItems[index].quantity <= 0) {
        _cartItems.removeAt(index);
      }
    });
  }

  void _clearCart() {
    setState(() {
      _cartItems.clear();
      _activeHoldOrderId = null; // Reset active hold order
      _selectedCustomer = 'Walk-in Customer (F2)';
    });
  }

  // ============ HOLD ORDER METHODS ============

  Future<void> _holdOrder() async {
    if (_cartItems.isEmpty || _orgId == null || _userId == null) return;

    final result = await _showHoldReasonDialog();
    if (result == null) return; // User cancelled

    // Parse the result: name||phone||reason
    final parts = result.split('||');
    final customerName = parts[0];
    final customerPhone = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    final holdReason = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;

    final now = DateTime.now();
    final orderId = const Uuid().v4();
    String? customerId;

    // Save customer to local DB
    final customer = Customer(
      id: const Uuid().v4(),
      orgId: _orgId!,
      storeId: _storeId,
      customerName: customerName,
      customerPhone: customerPhone,
      createdAt: now,
      updatedAt: now,
    );
    customerId = await _localDb.saveCustomer(customer);

    final holdOrder = HoldOrder(
      id: orderId,
      orgId: _orgId!,
      storeId: _storeId,
      userId: _userId!,
      userName: _userName,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      subTotal: subtotal,
      taxAmount: totalTaxAmount,
      cgstAmount: cgst,
      sgstAmount: sgst,
      totalAmount: totalAmount,
      holdReason: holdReason,
      createdAt: now,
      updatedAt: now,
      items: _cartItems.asMap().entries.map((entry) {
        final item = entry.value;
        return HoldOrderItem(
          id: const Uuid().v4(),
          holdOrderId: orderId,
          itemId: item.item.id,
          itemCode: item.item.itemCode,
          itemName: item.item.itemName,
          categoryName: item.item.category?.categoryName,
          quantity: item.quantity.toDouble(),
          unit: item.item.unit ?? 'PCS',
          unitPrice: item.item.sellingPrice,
          taxPercentage: item.item.taxRate ?? 5.0,
          totalAmount: item.totalPrice,
          imageUrl: item.item.imageUrl,
          createdAt: now,
        );
      }).toList(),
    );

    await _localDb.saveHoldOrder(holdOrder);
    await _loadHoldOrdersCount();
    
    // Sync customer to Supabase in background
    _customerService.syncCustomersToSupabase();
    
    _clearCart();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order held successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<String?> _showHoldReasonDialog() async {
    final reasonController = TextEditingController();
    final nameController = TextEditingController(text: _selectedCustomer == 'Walk-in Customer (F2)' ? '' : 
      (_selectedCustomer is Map ? _selectedCustomer['customer_name'] ?? '' : _selectedCustomer.toString()));
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hold Order'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items: ${_cartItems.length} | Total: ₹${totalAmount.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              // Customer Name (Required)
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Customer Name *',
                  hintText: 'Enter customer name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Customer name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Phone Number (Optional)
              TextFormField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number (Optional)',
                  hintText: 'Enter 10 digit phone number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.phone_outlined),
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value != null && value.isNotEmpty && value.length != 10) {
                    return 'Phone number must be 10 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Reason (Optional)
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Hold Reason (Optional)',
                  hintText: 'e.g., Customer will return',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.note_outlined),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                // Return data as JSON string
                final data = {
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'reason': reasonController.text.trim(),
                };
                Navigator.pop(context, '${data['name']}||${data['phone']}||${data['reason']}');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Hold Order'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHoldOrdersDialog() async {
    if (_orgId == null) return;

    final orders = await _localDb.getHoldOrders(_orgId!, storeId: _storeId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[600],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pause_circle_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(
                      'Hold Orders (${orders.length})',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Orders list
              Flexible(
                child: orders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No hold orders', style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return _buildHoldOrderTile(order, context);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHoldOrderTile(HoldOrder order, BuildContext dialogContext) {
    final indianDateTime = _formatIndianDateTime(order.createdAt);
    
    return GestureDetector(
      onTap: () {
        Navigator.pop(dialogContext);
        _restoreHoldOrder(order);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Items count badge
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.orange[100],
                child: Text(
                  '${order.items.length}',
                  style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              // Order details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer name and amount
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.customerName ?? 'Walk-in Customer',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        Text(
                          '₹${order.totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Phone number
                    if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            order.customerPhone!,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    // Date and time
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          indianDateTime,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                    // Hold reason
                    if (order.holdReason != null && order.holdReason!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.note, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              order.holdReason!,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Items summary
                    const SizedBox(height: 4),
                    Text(
                      order.items.map((i) => '${i.itemName} x${i.quantity.toInt()}').join(', '),
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.restore, color: Colors.green[600], size: 22),
                    tooltip: 'Restore to Cart',
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _restoreHoldOrder(order);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 22),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDeleteHoldOrder(order, dialogContext),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatIndianDateTime(DateTime dateTime) {
    // Convert to IST (UTC+5:30)
    final ist = dateTime.toLocal();
    
    final day = ist.day.toString().padLeft(2, '0');
    final month = _getMonthName(ist.month);
    final year = ist.year;
    
    final hour = ist.hour > 12 ? ist.hour - 12 : (ist.hour == 0 ? 12 : ist.hour);
    final minute = ist.minute.toString().padLeft(2, '0');
    final period = ist.hour >= 12 ? 'PM' : 'AM';
    
    return '$day $month $year, $hour:$minute $period';
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _restoreHoldOrder(HoldOrder order) async {
    // Convert hold order items back to cart items
    final restoredItems = <CartItem>[];
    
    for (var holdItem in order.items) {
      // Find the original item from loaded items or create a minimal one
      final originalItem = _items.firstWhere(
        (item) => item.id == holdItem.itemId,
        orElse: () => Item(
          id: holdItem.itemId,
          orgId: _orgId!,
          itemCode: holdItem.itemCode ?? '',
          itemName: holdItem.itemName,
          sellingPrice: holdItem.unitPrice,
          unit: holdItem.unit,
          imageUrl: holdItem.imageUrl,
          category: holdItem.categoryName != null 
              ? ItemCategory(id: '', orgId: _orgId!, categoryCode: '', categoryName: holdItem.categoryName!)
              : null,
        ),
      );
      
      restoredItems.add(CartItem(item: originalItem, quantity: holdItem.quantity.toInt()));
    }

    setState(() {
      _cartItems = restoredItems;
      _selectedCustomer = order.customerName ?? 'Walk-in Customer (F2)';
      _activeHoldOrderId = order.id; // Track which hold order is active
    });

    // DON'T delete the hold order here - keep it until payment is completed
    // await _localDb.deleteHoldOrder(order.id);
    // await _loadHoldOrdersCount();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order restored - Complete payment to remove from hold'),
          backgroundColor: Colors.orange[600],
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _confirmDeleteHoldOrder(HoldOrder order, BuildContext dialogContext) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Hold Order?'),
        content: Text('Delete order with ${order.items.length} items (₹${order.totalAmount.toStringAsFixed(2)})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _localDb.deleteHoldOrder(order.id);
      await _loadHoldOrdersCount();
      Navigator.pop(dialogContext);
      _showHoldOrdersDialog(); // Refresh the list
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // Single header with back button and window controls
          _buildHeader(),
          // Main Content
          Expanded(
            child: Row(
              children: [
                // Left Side - Products
                Expanded(
                  flex: 5, // Increased from 3 to 5 to give more space to products
                  child: Column(
                    children: [
                      // Category Tabs
                      _buildCategoryTabs(),
                      // Product Grid
                      Expanded(child: _buildProductGrid()),
                      // Bottom Shortcuts
                      _buildBottomShortcuts(),
                    ],
                  ),
                ),
                // Right Side - Active Order
                Container(
                  width: 400, // Reduced from 550 to 400 to make cart narrower
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(-2, 0),
                      ),
                    ],
                  ),
                  child: _buildActiveOrder(),
                ),
              ],
            ),
          ),
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
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          // Title with drag area
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
                    child: const Icon(Icons.point_of_sale, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Billing',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          // Debug button (developer mode)
          const DebugButton(),
          // Today's Orders button
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.white),
            tooltip: "Today's Orders",
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
            },
          ),
          const SizedBox(width: 8),
          // Window controls
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo and Title
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[600],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.point_of_sale, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            'Five Star POS',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 32),
          // Search Bar
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => _onSearchChanged(),
                decoration: InputDecoration(
                  hintText: 'Search products or SKU (F2)',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Nav Links
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Dashboard', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {},
            child: Text('Inventory', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {},
            child: Text('Orders', style: TextStyle(color: Colors.grey[700])),
          ),
          const SizedBox(width: 16),
          // Icons
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.dark_mode_outlined, color: Colors.grey[700]),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.grid_view, color: Colors.grey[700]),
          ),
          const SizedBox(width: 8),
          // User Avatar
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return CircleAvatar(
                backgroundColor: Colors.blue[600],
                child: Text(
                  authProvider.userProfile?.fullName?.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // All Categories option
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: const Text('All Categories'),
                selected: _selectedCategoryId == null,
                onSelected: (selected) {
                  _onCategoryChanged(null);
                },
                backgroundColor: Colors.grey[200],
                selectedColor: Colors.blue[600],
                labelStyle: TextStyle(
                  color: _selectedCategoryId == null ? Colors.white : Colors.grey[800],
                  fontWeight: _selectedCategoryId == null ? FontWeight.w600 : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            // Category options
            ..._categories.map((category) {
              final isSelected = _selectedCategoryId == category.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(category.categoryName),
                  selected: isSelected,
                  onSelected: (selected) {
                    _onCategoryChanged(selected ? category.id : null);
                  },
                  backgroundColor: Colors.grey[200],
                  selectedColor: Colors.blue[600],
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[800],
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }


  Widget _buildProductGrid() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No products found',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty 
                  ? 'Try adjusting your search terms'
                  : 'No products available in this category',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) {
          return _buildProductCard(_filteredItems[index]);
        },
      ),
    );
  }

  Widget _buildProductCard(Item item) {
    final categoryColor = _getCategoryColor(item.category?.categoryName ?? 'Other');
    
    return GestureDetector(
      onTap: () => _addToCart(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image with Category Badge
            Container(
              height: 120,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: item.imageUrl != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: CachedProductImage(
                              productId: item.id,
                              imageUrl: item.imageUrl!,
                              width: double.infinity,
                              height: 120,
                              fit: BoxFit.cover,
                              errorWidget: Container(
                                width: double.infinity,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_not_supported, size: 32, color: Colors.grey[500]),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Image Error',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : Container(
                            width: double.infinity,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image, size: 32, color: Colors.grey[500]),
                                const SizedBox(height: 4),
                                Text(
                                  'No Image',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  // Category Badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.isLowStock ? Colors.red : categoryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.isLowStock ? 'LOW STOCK' : (item.category?.categoryName ?? 'OTHER').toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Veg/Non-veg indicator
                  if (item.isVeg != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: item.isVeg! ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.isVeg! ? Icons.circle : Icons.stop,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Product Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.shortName != null && item.shortName != item.itemName) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.shortName!,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹${item.sellingPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.blue[600],
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (item.mrp != null && item.mrp! > item.sellingPrice) ...[
                            Text(
                              '₹${item.mrp!.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Stock: ${item.currentStock ?? 0}',
                        style: TextStyle(
                          color: item.isLowStock ? Colors.red : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String categoryName) {
    // Generate consistent colors for categories
    final colors = [
      Colors.blue[600]!,
      Colors.green[600]!,
      Colors.orange[600]!,
      Colors.purple[600]!,
      Colors.teal[600]!,
      Colors.indigo[600]!,
      Colors.pink[600]!,
      Colors.amber[600]!,
    ];
    
    final index = categoryName.hashCode % colors.length;
    return colors[index.abs()];
  }

  Widget _buildBottomShortcuts() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildShortcutButton('F2', 'Search', Colors.grey[700]!),
          const SizedBox(width: 12),
          _buildShortcutButton('SPACE', 'Checkout', Colors.blue[600]!),
          const SizedBox(width: 12),
          _buildShortcutButton('F4', 'Customers', Colors.grey[700]!),
        ],
      ),
    );
  }

  Widget _buildShortcutButton(String key, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrder() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Order',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _clearCart,
                icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                tooltip: 'Clear cart',
              ),
            ],
          ),
        ),
        // Customer Selection
        // Cart Items
        Expanded(
          child: _cartItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[400]), // Increased icon size
                      const SizedBox(height: 20),
                      Text(
                        'No items in cart',
                        style: TextStyle(
                          color: Colors.grey[600], 
                          fontSize: 18, // Increased from 16
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Click on products to add them',
                        style: TextStyle(
                          color: Colors.grey[500], 
                          fontSize: 15, // Increased from 13
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Cart Items List (1 column) - More space for product details
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _cartItems.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildCartItem(_cartItems[index], index),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        // Order Summary
        _buildOrderSummary(),
      ],
    );
  }

  Widget _buildCartItem(CartItem item, int index) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // Product Image (smaller for compact layout)
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: item.item.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedProductImage(
                      productId: item.item.id,
                      imageUrl: item.item.imageUrl!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.image_not_supported, size: 16, color: Colors.grey[600]),
                      ),
                    ),
                  )
                : Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.image, size: 16, color: Colors.grey[600]),
                  ),
          ),
          const SizedBox(width: 12),
          // Product Details - Expanded to use available space
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Name
                Text(
                  item.item.itemName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Price and Category Row
                Row(
                  children: [
                    // Unit Price
                    Text(
                      '₹${item.item.sellingPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Colors.blue[600],
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Category Badge (smaller)
                    if (item.item.category != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(item.item.category!.categoryName).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.item.category!.categoryName.toUpperCase(),
                          style: TextStyle(
                            color: _getCategoryColor(item.item.category!.categoryName),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Quantity Controls and Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Quantity Controls (compact)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _updateQuantity(index, -1),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.remove, size: 16, color: Colors.grey[700]),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _updateQuantity(index, 1),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.add, size: 16, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Total Price
                    Text(
                      '₹${item.totalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Column(
        children: [
          // Only Total Amount - Clean and Simple
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '₹${totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action Buttons
          Row(
            children: [
              // View Hold Orders button
              Stack(
                children: [
                  IconButton(
                    onPressed: _showHoldOrdersDialog,
                    icon: Icon(Icons.inventory_2_outlined, color: Colors.grey[700]),
                    tooltip: 'View Hold Orders',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_holdOrdersCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange[600],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_holdOrdersCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              // Hold Order button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _cartItems.isEmpty ? null : _holdOrder,
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Hold'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _cartItems.isEmpty ? null : () => _showCustomerSelectionFirst(),
                  icon: const Icon(Icons.payment),
                  label: const Text('Pay Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600], 
            fontSize: 15, // Increased from 13
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500, 
            fontSize: 15, // Increased from 13
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomerSelectionFirst() async {
    // Show customer selection dialog first
    final customerData = await _showCustomerSelectionDialog();
    
    if (customerData != null) {
      // Customer was selected/created, now show invoice preview
      await _showInvoicePreviewWithCustomer(
        customerData['name'] ?? 'Walk-in Customer',
        customerData['phone'] ?? '',
        customerData['paymentMode'] ?? 'Cash',
        customerData['selectedCustomer'],
      );
    }
  }

  Future<Map<String, dynamic>?> _showCustomerSelectionDialog() async {
    final searchController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedPaymentMode = 'Cash';
    List<Map<String, dynamic>> searchResults = [];
    Map<String, dynamic>? selectedCustomer;
    bool isSearching = false;
    String? phoneError;
    String? nameError;
    String? lastSearchQuery;

    // Pre-fill if customer already selected (from hold order restore)
    if (_selectedCustomer != 'Walk-in Customer (F2)') {
      if (_selectedCustomer is Map) {
        nameController.text = _selectedCustomer['customer_name'] ?? '';
      } else {
        nameController.text = _selectedCustomer.toString();
      }
    }

    return await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> searchCustomers(String query) async {
            if (query.length < 2 || _orgId == null) {
              setDialogState(() => searchResults = []);
              return;
            }
            
            // Debounce - don't search if same query
            if (query == lastSearchQuery) return;
            lastSearchQuery = query;
            
            setDialogState(() => isSearching = true);
            
            // Search from Supabase for better performance with large data
            final results = await _customerService.searchCustomers(_orgId!, query);
            
            // Only update if this is still the latest query
            if (query == lastSearchQuery) {
              setDialogState(() {
                searchResults = results;
                isSearching = false;
              });
            }
          }

          Future<bool> checkPhoneExists(String phone) async {
            if (phone.isEmpty || _orgId == null) return false;
            final existing = await _customerService.getCustomerByPhone(_orgId!, phone);
            // Return false if no existing customer found
            if (existing == null) return false;
            // Return false if the existing customer is the currently selected one
            if (selectedCustomer != null && existing['id'] == selectedCustomer!['id']) {
              debugPrint('✅ Phone belongs to selected customer: ${selectedCustomer!['customer_name']}');
              return false;
            }
            // Return true only if phone exists and belongs to a different customer
            debugPrint('⚠️ Phone exists for different customer: ${existing['customer_name']}');
            return true;
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.person_add, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text('Customer Details'),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Section Header
                    Row(
                      children: [
                        Text('CUSTOMER DETAILS', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (selectedCustomer != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 12, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text('Existing', style: TextStyle(fontSize: 10, color: Colors.green[700])),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // 1. SEARCH CUSTOMER (Number or Name)
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
                      ),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(30), // Limit search to 30 characters
                        ],
                        decoration: InputDecoration(
                          labelText: 'Search Customer',
                          hintText: 'Enter phone (10 digits) or name (max 30 chars)...',
                          helperText: 'Search by phone or name • Minimum 2 characters',
                          helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSearching)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              if (searchController.text.isNotEmpty && !isSearching)
                                IconButton(
                                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {
                                      searchResults = [];
                                      selectedCustomer = null;
                                      lastSearchQuery = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCustomer = null;
                            // Clear name and phone when searching
                            nameController.clear();
                            phoneController.clear();
                            nameError = null;
                            phoneError = null;
                          });
                          searchCustomers(value);
                        },
                      ),
                    ),
                    
                    // Search Results Count
                    if (searchController.text.length >= 2 && !isSearching)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          searchResults.isEmpty 
                              ? 'No customers found' 
                              : '${searchResults.length} customer${searchResults.length == 1 ? '' : 's'} found',
                          style: TextStyle(
                            fontSize: 12,
                            color: searchResults.isEmpty ? Colors.orange[600] : Colors.green[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    
                    // Search Results Dropdown
                    if (searchResults.isNotEmpty && selectedCustomer == null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1), 
                              blurRadius: 8, 
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.05),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.people, size: 16, color: Theme.of(context).primaryColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Select Customer',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Results List
                            Expanded(
                              child: Scrollbar(
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: searchResults.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
                                  itemBuilder: (context, index) {
                                    final customer = searchResults[index];
                                    final customerName = customer['customer_name'] ?? 'Unknown';
                                    final customerPhone = customer['customer_phone'] ?? '';
                                    final totalOrders = customer['total_orders'] ?? 0;
                                    
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                        child: Text(
                                          customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C',
                                          style: TextStyle(
                                            color: Theme.of(context).primaryColor, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        customerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (customerPhone.isNotEmpty)
                                            Row(
                                              children: [
                                                Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  customerPhone,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          if (totalOrders > 0)
                                            Row(
                                              children: [
                                                Icon(Icons.shopping_bag, size: 12, color: Colors.green[500]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$totalOrders order${totalOrders == 1 ? '' : 's'}',
                                                  style: TextStyle(fontSize: 11, color: Colors.green[600]),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                      trailing: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[400]),
                                      onTap: () {
                                        setDialogState(() {
                                          selectedCustomer = customer;
                                          nameController.text = customerName;
                                          phoneController.text = customerPhone;
                                          searchResults = [];
                                          searchController.clear();
                                          nameError = null;
                                          phoneError = null;
                                        });
                                        // Small delay to ensure state is updated before any validation
                                        Future.delayed(const Duration(milliseconds: 100), () {
                                          setDialogState(() {
                                            nameError = null;
                                            phoneError = null;
                                          });
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // No Results Message
                    if (searchResults.isEmpty && searchController.text.length >= 2 && !isSearching && selectedCustomer == null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person_add, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Customer not found. Fill details below to create new customer.',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // 2. CUSTOMER NAME
                    TextField(
                      controller: nameController,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(30), // Max 30 characters
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')), // Only letters and spaces
                      ],
                      decoration: InputDecoration(
                        labelText: 'Customer Name',
                        hintText: 'Enter customer name (max 30 chars)',
                        helperText: 'Maximum 30 characters, letters only',
                        helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.person_outline, color: Theme.of(context).primaryColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red, width: 2),
                        ),
                        errorText: nameError,
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          nameError = null;
                          // Validate name length
                          if (value.length > 30) {
                            nameError = 'Name cannot exceed 30 characters';
                          }
                          // Clear selected customer if manually editing
                          if (selectedCustomer != null && value != selectedCustomer!['customer_name']) {
                            selectedCustomer = null;
                          }
                        });
                      },
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 3. PHONE NUMBER
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly, // Only digits
                        LengthLimitingTextInputFormatter(10), // Exactly 10 digits
                      ],
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'Enter 10-digit phone number (optional)',
                        helperText: 'Exactly 10 digits required if provided',
                        helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.phone_outlined, color: Theme.of(context).primaryColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red, width: 2),
                        ),
                        errorText: phoneError,
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        counterText: phoneController.text.isNotEmpty ? '${phoneController.text.length}/10' : null,
                        counterStyle: TextStyle(
                          fontSize: 11,
                          color: phoneController.text.length == 10 ? Colors.green[600] : Colors.grey[500],
                        ),
                      ),
                      onChanged: (value) async {
                        setDialogState(() {
                          phoneError = null;
                          // Validate phone length
                          if (value.isNotEmpty && value.length != 10) {
                            phoneError = 'Phone number must be exactly 10 digits';
                          }
                          // Clear selected customer if manually editing
                          if (selectedCustomer != null && value != selectedCustomer!['customer_phone']) {
                            selectedCustomer = null;
                          }
                        });
                        
                        // Check if phone exists (only for new customers, not when editing existing customer data)
                        if (value.length == 10 && selectedCustomer == null) {
                          final exists = await checkPhoneExists(value);
                          if (exists) {
                            setDialogState(() {
                              phoneError = 'Phone number already exists';
                            });
                          }
                        }
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Payment Method
                    Text('PAYMENT METHOD', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildPaymentMethodChip('Cash', Icons.money, selectedPaymentMode, (mode) => setDialogState(() => selectedPaymentMode = mode)),
                        const SizedBox(width: 8),
                        _buildPaymentMethodChip('UPI', Icons.qr_code, selectedPaymentMode, (mode) => setDialogState(() => selectedPaymentMode = mode)),
                        const SizedBox(width: 8),
                        _buildPaymentMethodChip('Card', Icons.credit_card, selectedPaymentMode, (mode) => setDialogState(() => selectedPaymentMode = mode)),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Validate customer name
                  if (nameController.text.trim().isEmpty) {
                    setDialogState(() {
                      nameError = 'Customer name is required';
                    });
                    return;
                  }
                  
                  // Validate name length (max 30 characters)
                  if (nameController.text.trim().length > 30) {
                    setDialogState(() {
                      nameError = 'Customer name cannot exceed 30 characters';
                    });
                    return;
                  }
                  
                  // Validate name contains only letters and spaces
                  if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(nameController.text.trim())) {
                    setDialogState(() {
                      nameError = 'Name can only contain letters and spaces';
                    });
                    return;
                  }
                  
                  // Validate phone if provided (exactly 10 digits)
                  if (phoneController.text.isNotEmpty && phoneController.text.length != 10) {
                    setDialogState(() {
                      phoneError = 'Phone number must be exactly 10 digits';
                    });
                    return;
                  }
                  
                  // Validate phone contains only digits
                  if (phoneController.text.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(phoneController.text)) {
                    setDialogState(() {
                      phoneError = 'Phone number can only contain digits';
                    });
                    return;
                  }
                  
                  // Check for phone duplication (only for new customers, not existing ones)
                  if (phoneController.text.isNotEmpty && selectedCustomer == null) {
                    final exists = await checkPhoneExists(phoneController.text);
                    if (exists) {
                      setDialogState(() {
                        phoneError = 'Phone number already exists';
                      });
                      return;
                    }
                  }
                  
                  // Return customer data
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'phone': phoneController.text.trim(),
                    'paymentMode': selectedPaymentMode,
                    'selectedCustomer': selectedCustomer,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue to Invoice'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showInvoicePreviewWithCustomer(String customerName, String customerPhone, String paymentMode, Map<String, dynamic>? selectedCustomer) async {
    // Show invoice preview dialog with customer information
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => InvoicePreviewDialog(
        cartItems: _cartItems,
        customerName: customerName,
        customerPhone: customerPhone,
        onConfirmPayment: () => _checkMappingAndShowPaymentWithCustomer(customerName, customerPhone, paymentMode, selectedCustomer),
      ),
    );
  }

  Future<void> _showInvoicePreview() async {
    // Get current customer information (if any)
    String customerName = 'Walk-in Customer';
    String customerPhone = '';
    
    if (_selectedCustomer != 'Walk-in Customer (F2)') {
      if (_selectedCustomer is Map<String, dynamic>) {
        final customer = _selectedCustomer as Map<String, dynamic>;
        customerName = customer['customer_name'] ?? 'Walk-in Customer';
        customerPhone = customer['customer_phone'] ?? '';
      } else if (_selectedCustomer is String) {
        customerName = _selectedCustomer as String;
      }
    }

    // Show invoice preview dialog (customer selection will happen in payment dialog)
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => InvoicePreviewDialog(
        cartItems: _cartItems,
        customerName: customerName,
        customerPhone: customerPhone,
        onConfirmPayment: () => _checkMappingAndShowPayment(),
      ),
    );
  }

  Future<void> _checkMappingAndShowPayment() async {
    // Check for products without raw material mapping
    List<String> unmappedProducts = [];
    
    for (final cartItem in _cartItems) {
      if (cartItem.item.rawMaterialMapping == null || cartItem.item.rawMaterialMapping!.isEmpty) {
        unmappedProducts.add(cartItem.item.itemName);
      }
    }
    
    debugPrint('🔍 BILLING: Checking raw material mapping - ${unmappedProducts.length} unmapped products');
    
    // If there are unmapped products, show warning but allow to continue
    if (unmappedProducts.isNotEmpty) {
      debugPrint('⚠️ BILLING: Found unmapped products: ${unmappedProducts.join(', ')}');
      
      // Show a warning dialog but allow user to continue
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text('Raw Material Mapping Missing'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unmappedProducts.length == 1
                    ? 'The product "${unmappedProducts.first}" does not have raw material mapping.'
                    : '${unmappedProducts.length} products do not have raw material mapping.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'You can still proceed with the sale, but raw material stock will not be automatically reduced.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue Sale'),
            ),
          ],
        ),
      );
      
      if (shouldContinue != true) {
        return; // User cancelled
      }
    }
    
    // Proceed with payment
    _showPaymentDialog();
  }

  Future<void> _checkMappingAndShowPaymentWithCustomer(String customerName, String customerPhone, String paymentMode, Map<String, dynamic>? selectedCustomer) async {
    // Check for products without raw material mapping
    List<String> unmappedProducts = [];
    
    for (final cartItem in _cartItems) {
      if (cartItem.item.rawMaterialMapping == null || cartItem.item.rawMaterialMapping!.isEmpty) {
        unmappedProducts.add(cartItem.item.itemName);
      }
    }
    
    debugPrint('🔍 BILLING: Checking raw material mapping - ${unmappedProducts.length} unmapped products');
    
    // If there are unmapped products, show warning but allow to continue
    if (unmappedProducts.isNotEmpty) {
      debugPrint('⚠️ BILLING: Found unmapped products: ${unmappedProducts.join(', ')}');
      
      // Show a warning dialog but allow user to continue
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text('Raw Material Mapping Missing'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unmappedProducts.length == 1
                    ? 'The product "${unmappedProducts.first}" does not have raw material mapping.'
                    : '${unmappedProducts.length} products do not have raw material mapping.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'You can still proceed with the sale, but raw material stock will not be automatically reduced.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue Sale'),
            ),
          ],
        ),
      );
      
      if (shouldContinue != true) {
        return; // User cancelled
      }
    }
    
    // Proceed with payment using the customer data from the first dialog
    await _processPayment(customerName, customerPhone, paymentMode, selectedCustomer);
  }

  void _showPaymentDialog() {
    final searchController = TextEditingController(); // Separate search controller
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedPaymentMode = 'Cash';
    List<Map<String, dynamic>> searchResults = [];
    Map<String, dynamic>? selectedCustomer;
    bool isSearching = false;
    String? phoneError;
    String? nameError;
    String? lastSearchQuery;

    // Pre-fill if customer already selected (from hold order restore)
    if (_selectedCustomer != 'Walk-in Customer (F2)') {
      if (_selectedCustomer is Map) {
        nameController.text = _selectedCustomer['customer_name'] ?? '';
      } else {
        nameController.text = _selectedCustomer.toString();
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> searchCustomers(String query) async {
            if (query.length < 2 || _orgId == null) {
              setDialogState(() => searchResults = []);
              return;
            }
            
            // Debounce - don't search if same query
            if (query == lastSearchQuery) return;
            lastSearchQuery = query;
            
            setDialogState(() => isSearching = true);
            
            // Search from Supabase for better performance with large data
            final results = await _customerService.searchCustomers(_orgId!, query);
            
            // Only update if this is still the latest query
            if (query == lastSearchQuery) {
              setDialogState(() {
                searchResults = results;
                isSearching = false;
              });
            }
          }

          Future<bool> checkPhoneExists(String phone) async {
            if (phone.isEmpty || _orgId == null) return false;
            final existing = await _customerService.getCustomerByPhone(_orgId!, phone);
            // Return false if no existing customer found
            if (existing == null) return false;
            // Return false if the existing customer is the currently selected one
            if (selectedCustomer != null && existing['id'] == selectedCustomer!['id']) {
              debugPrint('✅ Phone belongs to selected customer: ${selectedCustomer!['customer_name']}');
              return false;
            }
            // Return true only if phone exists and belongs to a different customer
            debugPrint('⚠️ Phone exists for different customer: ${existing['customer_name']}');
            return true;
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.payment, color: Colors.green[600]),
                const SizedBox(width: 8),
                const Text('Payment'),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Total Amount
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount', style: TextStyle(fontSize: 16)),
                          Text(
                            '₹${totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green[700]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Customer Section Header
                    Row(
                      children: [
                        Text('CUSTOMER DETAILS', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (selectedCustomer != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 12, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text('Existing', style: TextStyle(fontSize: 10, color: Colors.green[700])),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // 1. SEARCH CUSTOMER (Number or Name)
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
                      ),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(30), // Limit search to 30 characters
                        ],
                        decoration: InputDecoration(
                          labelText: 'Search Customer',
                          hintText: 'Enter phone (10 digits) or name (max 30 chars)...',
                          helperText: 'Search by phone or name • Minimum 2 characters',
                          helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSearching)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              if (searchController.text.isNotEmpty && !isSearching)
                                IconButton(
                                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {
                                      searchResults = [];
                                      selectedCustomer = null;
                                      lastSearchQuery = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCustomer = null;
                            // Clear name and phone when searching
                            nameController.clear();
                            phoneController.clear();
                            nameError = null;
                            phoneError = null;
                          });
                          searchCustomers(value);
                        },
                      ),
                    ),
                    
                    // Search Results Count
                    if (searchController.text.length >= 2 && !isSearching)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          searchResults.isEmpty 
                              ? 'No customers found' 
                              : '${searchResults.length} customer${searchResults.length == 1 ? '' : 's'} found',
                          style: TextStyle(
                            fontSize: 12,
                            color: searchResults.isEmpty ? Colors.orange[600] : Colors.green[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    
                    // Search Results Dropdown
                    if (searchResults.isNotEmpty && selectedCustomer == null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1), 
                              blurRadius: 8, 
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.05),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.people, size: 16, color: Theme.of(context).primaryColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Select Customer',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Results List
                            Expanded(
                              child: Scrollbar(
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: searchResults.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
                                  itemBuilder: (context, index) {
                                    final customer = searchResults[index];
                                    final customerName = customer['customer_name'] ?? 'Unknown';
                                    final customerPhone = customer['customer_phone'] ?? '';
                                    final totalOrders = customer['total_orders'] ?? 0;
                                    
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                        child: Text(
                                          customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C',
                                          style: TextStyle(
                                            color: Theme.of(context).primaryColor, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        customerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (customerPhone.isNotEmpty)
                                            Row(
                                              children: [
                                                Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  customerPhone,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          if (totalOrders > 0)
                                            Row(
                                              children: [
                                                Icon(Icons.shopping_bag, size: 12, color: Colors.green[500]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$totalOrders order${totalOrders == 1 ? '' : 's'}',
                                                  style: TextStyle(fontSize: 11, color: Colors.green[600]),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                      trailing: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[400]),
                                      onTap: () {
                                        setDialogState(() {
                                          selectedCustomer = customer;
                                          nameController.text = customerName;
                                          phoneController.text = customerPhone;
                                          searchResults = [];
                                          searchController.clear();
                                          nameError = null;
                                          phoneError = null;
                                        });
                                        // Small delay to ensure state is updated before any validation
                                        Future.delayed(const Duration(milliseconds: 100), () {
                                          setDialogState(() {
                                            nameError = null;
                                            phoneError = null;
                                          });
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // No Results Message
                    if (searchResults.isEmpty && searchController.text.length >= 2 && !isSearching && selectedCustomer == null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person_add, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Customer not found. Fill details below to create new customer.',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // 2. CUSTOMER NAME
                    TextField(
                      controller: nameController,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(30), // Max 30 characters
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')), // Only letters and spaces
                      ],
                      decoration: InputDecoration(
                        labelText: 'Customer Name',
                        hintText: 'Enter customer name (max 30 chars)',
                        helperText: 'Maximum 30 characters, letters only',
                        helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.person_outline, color: Theme.of(context).primaryColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red, width: 2),
                        ),
                        errorText: nameError,
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          nameError = null;
                          // Validate name length
                          if (value.length > 30) {
                            nameError = 'Name cannot exceed 30 characters';
                          }
                          // Clear selected customer if manually editing
                          if (selectedCustomer != null && value != selectedCustomer!['customer_name']) {
                            selectedCustomer = null;
                          }
                        });
                      },
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 3. PHONE NUMBER
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly, // Only digits
                        LengthLimitingTextInputFormatter(10), // Exactly 10 digits
                      ],
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'Enter 10-digit phone number (optional)',
                        helperText: 'Exactly 10 digits required if provided',
                        helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.phone_outlined, color: Theme.of(context).primaryColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red, width: 2),
                        ),
                        errorText: phoneError,
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        counterText: phoneController.text.isNotEmpty ? '${phoneController.text.length}/10' : null,
                        counterStyle: TextStyle(
                          fontSize: 11,
                          color: phoneController.text.length == 10 ? Colors.green[600] : Colors.grey[500],
                        ),
                      ),
                      onChanged: (value) async {
                        setDialogState(() {
                          phoneError = null;
                          // Validate phone length
                          if (value.isNotEmpty && value.length != 10) {
                            phoneError = 'Phone number must be exactly 10 digits';
                          }
                          // Clear selected customer if manually editing
                          if (selectedCustomer != null && value != selectedCustomer!['customer_phone']) {
                            selectedCustomer = null;
                          }
                        });
                        
                        // Check if phone exists (only for new customers, not when editing existing customer data)
                        if (value.length == 10 && selectedCustomer == null) {
                          final exists = await checkPhoneExists(value);
                          if (exists) {
                            setDialogState(() {
                              phoneError = 'Phone number already exists';
                            });
                          }
                        }
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Payment Method
                    Text('PAYMENT METHOD', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildPaymentMethodChip('Cash', Icons.money, selectedPaymentMode, (mode) => setDialogState(() => selectedPaymentMode = mode)),
                        const SizedBox(width: 8),
                        _buildPaymentMethodChip('UPI', Icons.qr_code, selectedPaymentMode, (mode) => setDialogState(() => selectedPaymentMode = mode)),
                        const SizedBox(width: 8),
                        _buildPaymentMethodChip('Card', Icons.credit_card, selectedPaymentMode, (mode) => setDialogState(() => selectedPaymentMode = mode)),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Validate customer name
                  if (nameController.text.trim().isEmpty) {
                    setDialogState(() {
                      nameError = 'Customer name is required';
                    });
                    return;
                  }
                  
                  // Validate name length (max 30 characters)
                  if (nameController.text.trim().length > 30) {
                    setDialogState(() {
                      nameError = 'Customer name cannot exceed 30 characters';
                    });
                    return;
                  }
                  
                  // Validate name contains only letters and spaces
                  if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(nameController.text.trim())) {
                    setDialogState(() {
                      nameError = 'Name can only contain letters and spaces';
                    });
                    return;
                  }
                  
                  // Validate phone if provided (exactly 10 digits)
                  if (phoneController.text.isNotEmpty && phoneController.text.length != 10) {
                    setDialogState(() {
                      phoneError = 'Phone number must be exactly 10 digits';
                    });
                    return;
                  }
                  
                  // Validate phone contains only digits
                  if (phoneController.text.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(phoneController.text)) {
                    setDialogState(() {
                      phoneError = 'Phone number can only contain digits';
                    });
                    return;
                  }
                  
                  // Check for phone duplication (only for new customers, not existing ones)
                  if (phoneController.text.isNotEmpty && selectedCustomer == null) {
                    final exists = await checkPhoneExists(phoneController.text);
                    if (exists) {
                      setDialogState(() {
                        phoneError = 'Phone number already exists';
                      });
                      return;
                    }
                  }
                  
                  Navigator.pop(context);
                  await _processPayment(
                    nameController.text.trim(),
                    phoneController.text.trim(),
                    selectedPaymentMode,
                    selectedCustomer,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Complete Payment'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processPayment(String customerName, String customerPhone, String paymentMode, Map<String, dynamic>? selectedCustomer) async {
    try {
      // Extract customer name from _selectedCustomer
      String actualCustomerName = 'Walk-in Customer';
      if (customerName.isNotEmpty) {
        actualCustomerName = customerName;
      } else if (selectedCustomer != null && selectedCustomer['customer_name'] != null) {
        actualCustomerName = selectedCustomer['customer_name'];
      }
      print('DEBUG: Extracted customer name: "$actualCustomerName"');

      // Save new customer if name provided and not existing
      String? customerId;
      if (customerName.isNotEmpty && _orgId != null && selectedCustomer == null) {
        final now = DateTime.now();
        customerId = const Uuid().v4();
        final customer = Customer(
          id: customerId,
          orgId: _orgId!,
          storeId: _storeId,
          customerName: customerName,
          customerPhone: customerPhone.isNotEmpty ? customerPhone : null,
          totalOrders: 1,
          totalSpent: totalAmount,
          lastOrderAt: now,
          createdAt: now,
          updatedAt: now,
        );
        await _localDb.saveCustomer(customer);
        _customerService.syncCustomersToSupabase();
        debugPrint('✅ New customer saved: $customerName');
      } else if (selectedCustomer != null) {
        customerId = selectedCustomer['id'];
        // Update existing customer stats
        _customerService.updateCustomerStats(customerId!, totalAmount);
        debugPrint('✅ Existing customer: ${selectedCustomer['customer_name']}');
      }

      // Create sales order
      if (_storeId != null && _userId != null) {
        final orderData = SalesOrderData(
          storeId: _storeId!,
          orderType: 'dine_in',
          customerName: actualCustomerName,
          customerPhone: customerPhone.isNotEmpty ? customerPhone : (selectedCustomer?['customer_phone']),
          subTotal: subtotal,
          taxAmount: totalTaxAmount,
          cgstAmount: cgst,
          sgstAmount: sgst,
          totalAmount: totalAmount,
          finalAmount: totalAmount,
          paymentMode: paymentMode.toLowerCase(),
          billedBy: _userId!,
          cashierName: _userName,
          items: _cartItems.map((cartItem) => SalesOrderItemData(
            productId: cartItem.item.id,
            productName: cartItem.item.itemName,
            productCode: cartItem.item.itemCode,
            quantity: cartItem.quantity.toDouble(),
            uom: cartItem.item.unit ?? 'PCS',
            unitPrice: cartItem.item.sellingPrice,
            taxableAmount: cartItem.item.sellingPrice * cartItem.quantity,
            taxPercentage: cartItem.item.taxRate ?? 5.0,
            taxAmount: (cartItem.item.sellingPrice * cartItem.quantity) * 0.05,
            totalLineAmount: cartItem.totalPrice,
          )).toList(),
        );

        final orderResult = await _salesService.createSalesOrder(orderData);
        if (orderResult != null) {
          debugPrint('✅ Invoice: ${orderResult.invoiceNo}');

          // Reduce raw material stock for each cart item
          debugPrint('🔄 Processing stock reduction for ${_cartItems.length} items...');
          List<String> stockWarnings = [];
          
          for (final cartItem in _cartItems) {
            try {
              // Check stock availability first
              final stockCheck = await _stockReductionService.checkStockAvailability(
                storeId: _storeId!,
                productId: cartItem.item.id,
                requestedQuantity: cartItem.quantity.toDouble(),
              );
              
              if (!stockCheck['available']) {
                final shortages = stockCheck['shortages'] as List<Map<String, dynamic>>;
                for (final shortage in shortages) {
                  stockWarnings.add(
                    '${shortage['material_name']}: Need ${shortage['required']}, Available ${shortage['available']}'
                  );
                }
              }
              
              // Proceed with stock reduction
              final reductionResult = await _stockReductionService.reduceStockForSale(
                storeId: _storeId!,
                productId: cartItem.item.id,
                soldQuantity: cartItem.quantity.toDouble(),
                salesOrderId: orderResult.orderId,
                userId: _userId,
              );
              
              if (reductionResult['success']) {
                if (reductionResult['hasMapping']) {
                  debugPrint('✅ Stock reduced for: ${cartItem.item.itemName} (Qty: ${cartItem.quantity})');
                } else {
                  debugPrint('⚠️ No mapping for: ${cartItem.item.itemName} (sale completed without stock reduction)');
                }
              } else {
                debugPrint('❌ Stock reduction failed for: ${cartItem.item.itemName}');
                stockWarnings.add('${cartItem.item.itemName}: ${reductionResult['error'] ?? 'Stock reduction failed'}');
              }
            } catch (e) {
              debugPrint('❌ Stock reduction error for ${cartItem.item.itemName}: $e');
              stockWarnings.add('${cartItem.item.itemName}: Stock reduction failed');
            }
          }
          
          // Show stock warnings if any
          if (stockWarnings.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Stock Warnings:\n${stockWarnings.join('\n')}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 1),
              ),
            );
          }

          // Always try to print invoice - error handling will show message if printer not connected
          await _printInvoice(orderResult.invoiceNo, paymentMode, actualCustomerName);
        }
      }

      // Delete hold order if restored
      if (_activeHoldOrderId != null) {
        await _localDb.deleteHoldOrder(_activeHoldOrderId!);
        await _loadHoldOrdersCount();
        _activeHoldOrderId = null;
      }

      _clearCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment successful!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint('❌ Payment processing error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red, duration: Duration(seconds: 1)),
        );
      }
    }
  }

  void _showRawMaterialMappingDialog(List<String> unmappedProducts) {
    // If only one product, show a simpler dialog
    if (unmappedProducts.length == 1) {
      final productName = unmappedProducts.first;
      final product = _cartItems.firstWhere((item) => item.item.itemName == productName).item;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange[600], size: 28),
                const SizedBox(width: 8),
                const Text('Raw Material Mapping Required'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The product "$productName" needs raw material mapping for accurate stock tracking.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.orange[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          productName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Would you like to set up raw material mapping now?',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showPaymentDialog();
                },
                child: const Text('Continue Without Mapping'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _editProductMapping(product);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Setup Mapping'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Multiple products - show list to choose from
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[600], size: 28),
              const SizedBox(width: 8),
              const Text('Raw Material Mapping Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${unmappedProducts.length} products need raw material mapping for accurate stock tracking:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: unmappedProducts.map((productName) {
                    final product = _cartItems.firstWhere((item) => item.item.itemName == productName).item;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _editProductMapping(product);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16, color: Colors.orange[600]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  productName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[600]),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Click on a product above to set up its raw material mapping, or continue without mapping.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Continue with payment without mapping
                _showPaymentDialog();
              },
              child: const Text('Continue Without Mapping'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editProductMapping(Item product) async {
    debugPrint('🔧 BILLING: Opening ProductEditDialog for ${product.itemName}');
    debugPrint('🔧 BILLING: Product ID: ${product.id}');
    debugPrint('🔧 BILLING: Current mapping count: ${product.rawMaterialMapping?.length ?? 0}');
    debugPrint('🔧 BILLING: Org ID: $_orgId');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ProductEditDialog(
        product: product,
        orgId: _orgId!,
        productService: ProductService(),
      ),
    );
    
    debugPrint('🔧 BILLING: Dialog result: $result');
    
    if (result == true) {
      debugPrint('🔧 BILLING: Product was updated, refreshing items...');
      // Product was updated, refresh the items list
      await _loadItems();
      
      // Update cart items with refreshed data
      _updateCartItemsWithRefreshedData();
      
      debugPrint('🔧 BILLING: Items refreshed, checking updated product...');
      final updatedProduct = _items.firstWhere(
        (item) => item.id == product.id,
        orElse: () => product,
      );
      debugPrint('🔧 BILLING: Updated mapping count: ${updatedProduct.rawMaterialMapping?.length ?? 0}');
    } else {
      debugPrint('🔧 BILLING: Dialog was cancelled or failed');
    }
    
    // After editing, check mapping again and show payment if ready
    debugPrint('🔧 BILLING: Re-checking mapping status...');
    _checkMappingAndShowPayment();
  }

  void _updateCartItemsWithRefreshedData() {
    debugPrint('🔄 BILLING: Starting cart items update...');
    debugPrint('🔄 BILLING: Cart items count: ${_cartItems.length}');
    debugPrint('🔄 BILLING: Available items count: ${_items.length}');
    
    // Update cart items with the latest item data from _items
    for (int i = 0; i < _cartItems.length; i++) {
      final cartItem = _cartItems[i];
      debugPrint('🔄 BILLING: Looking for cart item: ${cartItem.item.itemName} (ID: ${cartItem.item.id})');
      
      final updatedItem = _items.firstWhere(
        (item) => item.id == cartItem.item.id,
        orElse: () {
          debugPrint('❌ BILLING: Updated item not found for ${cartItem.item.itemName}');
          return cartItem.item; // Keep original if not found
        },
      );
      
      // Debug: Check if mapping was updated
      final oldMappingCount = cartItem.item.rawMaterialMapping?.length ?? 0;
      final newMappingCount = updatedItem.rawMaterialMapping?.length ?? 0;
      
      debugPrint('🔄 BILLING: ${cartItem.item.itemName}: ${oldMappingCount} → ${newMappingCount} mappings');
      
      if (updatedItem.id == cartItem.item.id) {
        debugPrint('✅ BILLING: Found matching item: ${updatedItem.itemName}');
        debugPrint('✅ BILLING: Updated item mapping count: ${updatedItem.rawMaterialMapping?.length ?? 0}');
        if (updatedItem.rawMaterialMapping != null) {
          for (int j = 0; j < updatedItem.rawMaterialMapping!.length; j++) {
            final mapping = updatedItem.rawMaterialMapping![j];
            debugPrint('✅ BILLING: Mapping $j: ${mapping.materialName} - ${mapping.quantity} ${mapping.uom}');
          }
        }
      }
      
      // Update the cart item with the refreshed item data
      _cartItems[i] = CartItem(
        item: updatedItem,
        quantity: cartItem.quantity,
      );
    }
    
    // Trigger UI update
    setState(() {});
    
    debugPrint('✅ BILLING: Cart items updated with refreshed mapping data');
    
    // Debug: Check final cart state
    for (int i = 0; i < _cartItems.length; i++) {
      final cartItem = _cartItems[i];
      debugPrint('🔍 BILLING: Final cart item $i: ${cartItem.item.itemName} - ${cartItem.item.rawMaterialMapping?.length ?? 0} mappings');
    }
  }

  Widget _buildPaymentMethodChip(String label, IconData icon, String selected, Function(String) onSelect) {
    final isSelected = selected == label;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[600] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? Colors.blue[600]! : Colors.grey[300]!),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.grey[700], size: 24),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dateTime.day.toString().padLeft(2, '0')}-${months[dateTime.month - 1]}-${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '${hour}:${dateTime.minute.toString().padLeft(2, '0')} $period';
  }
}