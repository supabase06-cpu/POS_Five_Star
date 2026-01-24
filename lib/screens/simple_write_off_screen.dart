import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/simple_write_off_model.dart';
import '../models/inward_model.dart';
import '../services/simple_write_off_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';
import '../widgets/write_off_csv_export_button.dart';

class SimpleWriteOffScreen extends StatefulWidget {
  const SimpleWriteOffScreen({super.key});

  @override
  State<SimpleWriteOffScreen> createState() => _SimpleWriteOffScreenState();
}

class _SimpleWriteOffScreenState extends State<SimpleWriteOffScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SimpleWriteOffService _writeOffService = SimpleWriteOffService();
  
  String? _storeId;
  String? _orgId;
  String? _userId;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeData();
  }

  void _initializeData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _storeId = authProvider.userProfile?.organizationId;
    _orgId = authProvider.userProfile?.organizationId;
    _userId = authProvider.user?.id;
    _userName = authProvider.userProfile?.fullName;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _NewWriteOffTab(
                  storeId: _storeId,
                  orgId: _orgId,
                  userId: _userId,
                  userName: _userName,
                  writeOffService: _writeOffService,
                ),
                _WriteOffHistoryTab(
                  storeId: _storeId,
                  writeOffService: _writeOffService,
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
      color: Colors.red[600],
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
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Write Off',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const DebugButton(),
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.red[600],
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        tabs: const [
          Tab(text: 'New Write Off', icon: Icon(Icons.add_circle_outline, size: 20)),
          Tab(text: 'History', icon: Icon(Icons.history, size: 20)),
        ],
      ),
    );
  }
}

// ============ NEW WRITE OFF TAB ============
class _NewWriteOffTab extends StatefulWidget {
  final String? storeId;
  final String? orgId;
  final String? userId;
  final String? userName;
  final SimpleWriteOffService writeOffService;

  const _NewWriteOffTab({
    required this.storeId,
    required this.orgId,
    required this.userId,
    required this.userName,
    required this.writeOffService,
  });

  @override
  State<_NewWriteOffTab> createState() => _NewWriteOffTabState();
}

class _NewWriteOffTabState extends State<_NewWriteOffTab> {
  final TextEditingController _searchController = TextEditingController();
  
  List<InwardProduct> _products = [];
  List<SimpleWriteOffCartItem> _cartItems = [];
  
  String _selectedReason = WriteOffReason.damaged;
  bool _isLoadingProducts = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts([String? query]) async {
    if (widget.orgId == null) return;
    setState(() => _isLoadingProducts = true);
    
    final products = await widget.writeOffService.getProductsForWriteOff(
      widget.orgId!, 
      searchQuery: query,
    );
    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
  }

  void _addToCart(InwardProduct product) {
    // Check if already added
    final existingIndex = _cartItems.indexWhere((item) => item.productId == product.id);
    if (existingIndex >= 0) {
      final currentQty = _cartItems[existingIndex].quantity;
      if (currentQty >= product.currentStock) {
        _showError('Cannot exceed available stock: ${product.currentStock.toStringAsFixed(0)} ${product.uom}');
        return;
      }
      setState(() {
        _cartItems[existingIndex].quantity++;
      });
    } else {
      if (product.currentStock <= 0) {
        _showError('No stock available for ${product.productName}');
        return;
      }
      setState(() {
        _cartItems.add(SimpleWriteOffCartItem(
          productId: product.id,
          productName: product.productName,
          productCode: product.productCode,
          quantity: 0, // Start with 0 instead of 1
          uom: product.uom,
          writeOffReason: _selectedReason,
          availableStock: product.currentStock,
          unitCost: product.costPrice,
        ));
      });
    }
  }

  void _removeFromCart(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  void _updateCartItem(int index, {double? quantity, String? reason}) {
    setState(() {
      if (quantity != null) _cartItems[index].quantity = quantity;
      if (reason != null) _cartItems[index].writeOffReason = reason;
    });
  }

  Future<void> _saveWriteOff() async {
    if (_cartItems.isEmpty) {
      _showError('Please add items to write off');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final writeOffNumber = await widget.writeOffService.generateWriteOffNumber(widget.storeId!);
      
      final writeOffId = await widget.writeOffService.createWriteOff(
        storeId: widget.storeId!,
        writeOffNumber: writeOffNumber,
        writeOffDate: DateTime.now(),
        writeOffReason: _selectedReason,
        requestedBy: widget.userId!,
        remarks: null,
        items: _cartItems,
      );

      if (writeOffId != null) {
        _showSuccess('Write off created successfully: $writeOffNumber');
        _clearForm();
        // Refresh products to show updated quantities
        await _loadProducts();
      } else {
        _showError('Failed to create write off');
      }
    } catch (e) {
      _showError('Error creating write off: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _clearForm() {
    setState(() {
      _cartItems.clear();
      _selectedReason = WriteOffReason.damaged;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Panel - Product Selection
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildProductSearch(),
                Expanded(child: _buildProductList()),
              ],
            ),
          ),
        ),
        // Right Panel - Write Off Cart
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[50],
            child: Column(
              children: [
                _buildCartHeader(),
                Expanded(child: _buildCart()),
                _buildCartFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductSearch() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search raw materials...',
          prefixIcon: Icon(Icons.search, color: Colors.red[600]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red[600]!, width: 2),
          ),
        ),
        onChanged: (value) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_searchController.text == value) {
              _loadProducts(value.isEmpty ? null : value);
            }
          });
        },
      ),
    );
  }

  Widget _buildProductList() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No raw materials found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red[100],
              child: Text(
                product.productName[0].toUpperCase(),
                style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(product.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${product.productCode} • ${product.uom}'),
                if (product.currentStock > 0)
                  Text(
                    'Stock: ${product.currentStock.toStringAsFixed(2)} ${product.uom}',
                    style: TextStyle(
                      color: product.currentStock > 10 ? Colors.green[600] : Colors.orange[600],
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            trailing: ElevatedButton.icon(
              onPressed: () => _addToCart(product),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[600],
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.delete_outline, color: Colors.white),
          const SizedBox(width: 8),
          const Text(
            'Write Off Items',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_cartItems.length}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCart() {
    if (_cartItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No items to write off',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Select raw materials from the left panel',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cartItems.length,
      itemBuilder: (context, index) {
        final item = _cartItems[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          Text(
                            '${item.productCode} • ${item.uom}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          Text(
                            'Available: ${item.availableStock.toStringAsFixed(2)} ${item.uom}',
                            style: TextStyle(
                              color: item.availableStock > 10 ? Colors.green[600] : Colors.orange[600],
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removeFromCart(index),
                      icon: Icon(Icons.close, color: Colors.red[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Quantity',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: item.uom.toUpperCase() == 'PCS' 
                                  ? TextInputType.number 
                                  : const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: item.uom.toUpperCase() == 'PCS'
                                  ? [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ]
                                  : [
                                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                    ],
                              onChanged: (value) {
                                final qty = double.tryParse(value) ?? 0;
                                if (qty > 0) {
                                  // For PCS, ensure it's a whole number
                                  if (item.uom.toUpperCase() == 'PCS' && qty != qty.floor()) {
                                    _showError('PCS quantities must be whole numbers');
                                    return;
                                  }
                                  
                                  if (qty > item.availableStock) {
                                    _showError('Cannot exceed available stock: ${item.availableStock.toStringAsFixed(2)} ${item.uom}');
                                    return;
                                  }
                                  _updateCartItem(index, quantity: qty);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              item.uom,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: item.writeOffReason,
                        decoration: const InputDecoration(
                          labelText: 'Write Off Reason',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: WriteOffReason.allReasons.map((reason) {
                          return DropdownMenuItem(
                            value: reason,
                            child: Text(WriteOffReason.getDisplayName(reason)),
                          );
                        }).toList(),
                        onChanged: (reason) {
                          if (reason != null) {
                            _updateCartItem(index, reason: reason);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartFooter() {
    final totalItems = _cartItems.fold<double>(0, (sum, item) => sum + item.quantity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total and Save Button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Items',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '${totalItems.toStringAsFixed(2)} items',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _isSaving || _cartItems.isEmpty ? null : _saveWriteOff,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create Write Off'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============ WRITE OFF HISTORY TAB ============
class _WriteOffHistoryTab extends StatefulWidget {
  final String? storeId;
  final SimpleWriteOffService writeOffService;

  const _WriteOffHistoryTab({
    required this.storeId,
    required this.writeOffService,
  });

  @override
  State<_WriteOffHistoryTab> createState() => _WriteOffHistoryTabState();
}

class _WriteOffHistoryTabState extends State<_WriteOffHistoryTab> {
  List<SimpleWriteOffHeader> _writeOffs = [];
  bool _isLoading = true;
  
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    // Set default date range to last 6 months
    final now = DateTime.now();
    _toDate = now;
    _fromDate = DateTime(now.year, now.month - 6, now.day);
    _loadWriteOffs();
  }

  Future<void> _loadWriteOffs() async {
    if (widget.storeId == null) return;
    
    setState(() => _isLoading = true);
    final writeOffs = await widget.writeOffService.getWriteOffHistory(
      storeId: widget.storeId!,
      fromDate: _fromDate,
      toDate: _toDate,
    );
    setState(() {
      _writeOffs = writeOffs;
      _isLoading = false;
    });
  }

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now().subtract(const Duration(days: 180)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      _loadWriteOffs();
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _toDate = picked;
      });
      _loadWriteOffs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterHeader(),
        Expanded(child: _buildHistoryList()),
      ],
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, color: Colors.grey),
              const SizedBox(width: 8),
              const Text(
                'Filter Write-offs',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              WriteOffCsvExportButton(
                storeId: widget.storeId,
                writeOffs: _writeOffs,
                writeOffService: widget.writeOffService,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _selectFromDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _fromDate != null ? _formatDate(_fromDate!) : 'From Date',
                          style: TextStyle(
                            color: _fromDate != null ? Colors.black87 : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text('to', style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _selectToDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _toDate != null ? _formatDate(_toDate!) : 'To Date',
                          style: TextStyle(
                            color: _toDate != null ? Colors.black87 : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_writeOffs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Found ${_writeOffs.length} write-off records',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_writeOffs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No write offs found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting the date range',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _writeOffs.length,
      itemBuilder: (context, index) {
        final writeOff = _writeOffs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red[100],
              child: Icon(Icons.delete_outline, color: Colors.red[700]),
            ),
            title: Text(
              writeOff.writeOffNumber,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${WriteOffReason.getDisplayName(writeOff.writeOffReason)} • ${writeOff.items.length} items'),
                Text(
                  '${_formatDate(writeOff.writeOffDate)} • By: ${writeOff.requestedByName ?? 'Unknown User'}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            trailing: Text(
              _formatDateTime(writeOff.createdAt),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}