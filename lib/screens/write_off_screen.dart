import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/write_off_model.dart';
import '../models/inward_model.dart';
import '../services/write_off_service.dart';
import '../services/inward_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';

class WriteOffScreen extends StatefulWidget {
  const WriteOffScreen({super.key});

  @override
  State<WriteOffScreen> createState() => _WriteOffScreenState();
}

class _WriteOffScreenState extends State<WriteOffScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WriteOffService _writeOffService = WriteOffService();
  final InwardService _inwardService = InwardService();
  
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
  final WriteOffService writeOffService;

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
  final TextEditingController _remarksController = TextEditingController();
  
  List<InwardProduct> _products = [];
  List<WriteOffCartItem> _cartItems = [];
  
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
    _remarksController.dispose();
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

  Future<void> _addProductToCart(InwardProduct product) async {
    // Check if product is already in cart
    final existingIndex = _cartItems.indexWhere((item) => item.productId == product.id);
    
    if (existingIndex >= 0) {
      // Update existing item quantity
      setState(() {
        final currentQty = _cartItems[existingIndex].quantity;
        if (currentQty < product.currentStock) {
          _cartItems[existingIndex].quantity = currentQty + 1;
        }
      });
    } else {
      // Add new item to cart
      setState(() {
        _cartItems.add(WriteOffCartItem(
          productId: product.id,
          productName: product.productName,
          productCode: product.productCode,
          quantity: 1,
          unitCost: product.costPrice,
          availableQuantity: product.currentStock,
          uom: product.uom,
          writeOffReason: _selectedReason,
        ));
      });
    }
  }

  void _removeFromCart(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  void _updateCartItem(int index, {double? quantity, String? reason, String? remarks}) {
    setState(() {
      if (quantity != null) _cartItems[index].quantity = quantity;
      if (reason != null) _cartItems[index].writeOffReason = reason;
      if (remarks != null) _cartItems[index].remarks = remarks;
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
      final subTotal = _cartItems.fold<double>(0, (sum, item) => sum + item.totalAmount);
      
      final writeOffId = await widget.writeOffService.createWriteOff(
        storeId: widget.storeId!,
        writeOffNumber: writeOffNumber,
        writeOffDate: DateTime.now(),
        writeOffReason: _selectedReason,
        subTotal: subTotal,
        totalAmount: subTotal,
        requestedBy: widget.userId!,
        remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
        items: _cartItems,
      );

      if (writeOffId != null) {
        _showSuccess('Write off created successfully: $writeOffNumber');
        _clearForm();
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
    _remarksController.clear();
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
          hintText: 'Search products...',
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
              'No products with stock found',
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
            subtitle: Text('${product.productCode} • Stock: ${product.currentStock.toStringAsFixed(2)} ${product.uom}'),
            trailing: ElevatedButton.icon(
              onPressed: () => _addProductToCart(product),
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
              'Select products from the left panel',
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
                            '${item.productCode} • Available: ${item.availableQuantity.toStringAsFixed(2)} ${item.uom}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                      child: TextFormField(
                        initialValue: item.quantity.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        onChanged: (value) {
                          final qty = double.tryParse(value) ?? 0;
                          if (qty > 0 && qty <= item.availableQuantity) {
                            _updateCartItem(index, quantity: qty);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: item.remarks ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Remarks (Optional)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _updateCartItem(index, remarks: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available: ${item.availableQuantity.toStringAsFixed(2)} ${item.uom}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      'Total: ₹${item.totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
    final totalAmount = _cartItems.fold<double>(0, (sum, item) => sum + item.totalAmount);

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
          // Reason Selection
          DropdownButtonFormField<String>(
            value: _selectedReason,
            decoration: const InputDecoration(
              labelText: 'Write Off Reason',
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
                setState(() => _selectedReason = reason);
                // Update all cart items with new reason
                for (int i = 0; i < _cartItems.length; i++) {
                  _updateCartItem(i, reason: reason);
                }
              }
            },
          ),
          const SizedBox(height: 12),
          // Remarks
          TextField(
            controller: _remarksController,
            decoration: const InputDecoration(
              labelText: 'Remarks (Optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          // Total and Save Button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Write Off Amount',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '₹${totalAmount.toStringAsFixed(2)}',
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
  final WriteOffService writeOffService;

  const _WriteOffHistoryTab({
    required this.storeId,
    required this.writeOffService,
  });

  @override
  State<_WriteOffHistoryTab> createState() => _WriteOffHistoryTabState();
}

class _WriteOffHistoryTabState extends State<_WriteOffHistoryTab> {
  List<WriteOffHeader> _writeOffs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWriteOffs();
  }

  Future<void> _loadWriteOffs() async {
    if (widget.storeId == null) return;
    
    setState(() => _isLoading = true);
    final writeOffs = await widget.writeOffService.getWriteOffHistory(storeId: widget.storeId!);
    setState(() {
      _writeOffs = writeOffs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              backgroundColor: _getStatusColor(writeOff.writeOffStatus),
              child: Icon(
                _getStatusIcon(writeOff.writeOffStatus),
                color: Colors.white,
              ),
            ),
            title: Text(
              writeOff.writeOffNumber,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${WriteOffReason.getDisplayName(writeOff.writeOffReason)}'),
                Text(
                  _formatDate(writeOff.writeOffDate),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${writeOff.totalWriteOffAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(writeOff.writeOffStatus).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    writeOff.writeOffStatus.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(writeOff.writeOffStatus),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}