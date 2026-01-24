import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/inward_model.dart';
import '../services/inward_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';
import '../widgets/add_supplier_dialog.dart';
import '../widgets/inward_csv_export_button.dart';

// Custom formatter to convert text to uppercase as user types
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class InwardScreen extends StatefulWidget {
  const InwardScreen({super.key});

  @override
  State<InwardScreen> createState() => _InwardScreenState();
}

class _InwardScreenState extends State<InwardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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
                _NewInwardTab(
                  storeId: _storeId,
                  orgId: _orgId,
                  userId: _userId,
                  userName: _userName,
                  inwardService: _inwardService,
                ),
                _InwardHistoryTab(
                  storeId: _storeId,
                  inwardService: _inwardService,
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
                    child: const Icon(Icons.inventory_2, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Stock Inward',
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
      color: Colors.orange[600],
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        tabs: const [
          Tab(text: 'New Inward', icon: Icon(Icons.add_box, size: 20)),
          Tab(text: 'History', icon: Icon(Icons.history, size: 20)),
        ],
      ),
    );
  }
}


// ============ NEW INWARD TAB - STEP BASED LAYOUT ============
class _NewInwardTab extends StatefulWidget {
  final String? storeId;
  final String? orgId;
  final String? userId;
  final String? userName;
  final InwardService inwardService;

  const _NewInwardTab({
    required this.storeId,
    required this.orgId,
    required this.userId,
    required this.userName,
    required this.inwardService,
  });

  @override
  State<_NewInwardTab> createState() => _NewInwardTabState();
}

class _NewInwardTabState extends State<_NewInwardTab> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _invoiceController = TextEditingController();
  final TextEditingController _supplierSearchController = TextEditingController();
  final ScrollController _cartScrollController = ScrollController();
  final LayerLink _supplierLayerLink = LayerLink();
  
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  List<InwardProduct> _products = [];
  List<InwardCartItem> _cartItems = [];
  
  Supplier? _selectedSupplier;
  bool _isLoadingSuppliers = true;
  bool _isLoadingProducts = false;
  bool _isSaving = false;
  bool _showSupplierDropdown = false;
  OverlayEntry? _supplierOverlayEntry;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _invoiceController.dispose();
    _supplierSearchController.dispose();
    _cartScrollController.dispose();
    _removeSupplierOverlay();
    super.dispose();
  }

  void _removeSupplierOverlay() {
    _supplierOverlayEntry?.remove();
    _supplierOverlayEntry = null;
    _showSupplierDropdown = false;
  }

  Future<void> _loadSuppliers() async {
    if (widget.orgId == null) return;
    setState(() => _isLoadingSuppliers = true);
    
    final suppliers = await widget.inwardService.getSuppliers(widget.orgId!);
    setState(() {
      _suppliers = suppliers;
      _filteredSuppliers = suppliers;
      _isLoadingSuppliers = false;
    });
  }

  void _filterSuppliers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSuppliers = _suppliers;
      } else {
        _filteredSuppliers = _suppliers.where((s) =>
            s.supplierName.toLowerCase().contains(query.toLowerCase()) ||
            s.supplierCode.toLowerCase().contains(query.toLowerCase()) ||
            (s.phone?.contains(query) ?? false)
        ).toList();
      }
    });
    _updateSupplierOverlay();
  }

  void _showSupplierDropdownOverlay() {
    _removeSupplierOverlay();
    _showSupplierDropdown = true;
    _supplierOverlayEntry = _createSupplierOverlay();
    Overlay.of(context).insert(_supplierOverlayEntry!);
  }

  void _updateSupplierOverlay() {
    _supplierOverlayEntry?.markNeedsBuild();
  }

  OverlayEntry _createSupplierOverlay() {
    return OverlayEntry(
      builder: (context) => Positioned(
        width: 400,
        child: CompositedTransformFollower(
          link: _supplierLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _supplierSearchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search supplier...',
                        prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor, size: 20),
                        suffixIcon: _supplierSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: Colors.grey[600], size: 18),
                                onPressed: () {
                                  _supplierSearchController.clear();
                                  _filterSuppliers('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), 
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onChanged: _filterSuppliers,
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey[200]),
                  // Supplier list
                  Flexible(
                    child: _filteredSuppliers.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('No suppliers found', style: TextStyle(color: Colors.grey[500])),
                          )
                        : Column(
                            children: [
                              // Add New Supplier Option
                              InkWell(
                                onTap: () async {
                                  _removeSupplierOverlay();
                                  final newSupplier = await showDialog<Supplier>(
                                    context: context,
                                    builder: (context) => AddSupplierDialog(
                                      orgId: widget.orgId!,
                                      storeId: widget.storeId,
                                    ),
                                  );
                                  if (newSupplier != null) {
                                    setState(() {
                                      _suppliers.insert(0, newSupplier);
                                      _filteredSuppliers = _suppliers;
                                      _selectedSupplier = newSupplier;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.green[100],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.add, color: Colors.green[700], size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Add New Supplier', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green[800])),
                                            Text('Create a new supplier', style: TextStyle(fontSize: 11, color: Colors.green[600])),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios, color: Colors.green[600], size: 16),
                                    ],
                                  ),
                                ),
                              ),
                              // Existing Suppliers
                              Flexible(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: _filteredSuppliers.length,
                                  itemBuilder: (context, index) {
                                    final supplier = _filteredSuppliers[index];
                                    final isSelected = _selectedSupplier?.id == supplier.id;
                                    return InkWell(
                                      onTap: () {
                                        setState(() => _selectedSupplier = supplier);
                                        _supplierSearchController.clear();
                                        _removeSupplierOverlay();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        color: isSelected ? Colors.orange[50] : null,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: isSelected ? Colors.orange[100] : Colors.grey[100],
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  supplier.supplierName[0].toUpperCase(),
                                                  style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.orange[700] : Colors.grey[600]),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(supplier.supplierName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSelected ? Colors.orange[800] : Colors.grey[800])),
                                                  Text('${supplier.supplierCode}${supplier.phone != null ? ' • ${supplier.phone}' : ''}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                                ],
                                              ),
                                            ),
                                            // Edit button
                                            InkWell(
                                              onTap: () async {
                                                _removeSupplierOverlay();
                                                final updatedSupplier = await showDialog<Supplier>(
                                                  context: context,
                                                  builder: (context) => AddSupplierDialog(
                                                    orgId: widget.orgId!,
                                                    storeId: widget.storeId,
                                                    editSupplier: supplier,
                                                  ),
                                                );
                                                if (updatedSupplier != null) {
                                                  setState(() {
                                                    final index = _suppliers.indexWhere((s) => s.id == supplier.id);
                                                    if (index >= 0) {
                                                      _suppliers[index] = updatedSupplier;
                                                      _filteredSuppliers = _suppliers;
                                                      if (_selectedSupplier?.id == supplier.id) {
                                                        _selectedSupplier = updatedSupplier;
                                                      }
                                                    }
                                                  });
                                                }
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue[50],
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Icon(Icons.edit, color: Colors.blue[600], size: 16),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isSelected) Icon(Icons.check_circle, color: Colors.orange[600], size: 18),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadProducts([String? query]) async {
    if (widget.orgId == null) return;
    setState(() => _isLoadingProducts = true);
    
    final products = await widget.inwardService.getProducts(widget.orgId!, searchQuery: query);
    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
  }

  void _addToCart(InwardProduct product) {
    setState(() {
      final existingIndex = _cartItems.indexWhere((item) => item.product.id == product.id);
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity++;
      } else {
        _cartItems.add(InwardCartItem(product: product));
      }
    });
    // Scroll to bottom of cart
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_cartScrollController.hasClients) {
        _cartScrollController.animateTo(
          _cartScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeFromCart(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  void _updateCartItem(int index, {double? quantity, double? unitCost, double? discount}) {
    setState(() {
      if (quantity != null) _cartItems[index].quantity = quantity;
      if (unitCost != null) _cartItems[index].unitCost = unitCost;
      if (discount != null) _cartItems[index].discountPercentage = discount;
    });
  }

  Future<void> _showBatchDialog(int index) async {
    final item = _cartItems[index];
    final batchController = TextEditingController(text: item.batchNo ?? '');
    DateTime? mfdDate = item.manufacturingDate;
    DateTime? expDate = item.expiryDate;
    DateTime? openDate = item.openDate;
    String? errorMessage;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.qr_code_2, color: Colors.blue[600]),
              const SizedBox(width: 10),
              const Text('Batch Information'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Required',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                Text(
                  item.product.productCode,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 20),
                // Error message
                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(errorMessage!, style: TextStyle(color: Colors.red[700], fontSize: 13))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Batch Number
                TextField(
                  controller: batchController,
                  decoration: InputDecoration(
                    labelText: 'Batch Number *',
                    hintText: 'Enter batch number',
                    prefixIcon: const Icon(Icons.numbers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    errorText: batchController.text.trim().isEmpty ? 'Required' : null,
                  ),
                  onChanged: (value) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                // Manufacturing Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: mfdDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setDialogState(() => mfdDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: mfdDate == null ? Colors.red[300]! : Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Manufacturing Date', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  const SizedBox(width: 4),
                                  Text('*', style: TextStyle(color: Colors.red[600], fontSize: 12)),
                                ],
                              ),
                              Text(
                                mfdDate != null ? _formatDate(mfdDate!) : 'Select date',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mfdDate != null ? Colors.black87 : Colors.red[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (mfdDate != null)
                          InkWell(
                            onTap: () => setDialogState(() => mfdDate = null),
                            child: Icon(Icons.clear, color: Colors.grey[400], size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Expiry Date
                InkWell(
                  onTap: () async {
                    final minDate = mfdDate != null ? mfdDate!.add(const Duration(days: 1)) : DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expDate ?? minDate,
                      firstDate: minDate,
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (picked != null) {
                      setDialogState(() => expDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: expDate == null ? Colors.red[300]! : Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_available, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Expiry Date', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  const SizedBox(width: 4),
                                  Text('*', style: TextStyle(color: Colors.red[600], fontSize: 12)),
                                ],
                              ),
                              Text(
                                expDate != null ? _formatDate(expDate!) : 'Select date',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: expDate != null ? Colors.black87 : Colors.red[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (expDate != null)
                          InkWell(
                            onTap: () => setDialogState(() => expDate = null),
                            child: Icon(Icons.clear, color: Colors.grey[400], size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Open Date
                InkWell(
                  onTap: () async {
                    final minDate = mfdDate != null ? mfdDate!.add(const Duration(days: 1)) : DateTime.now().subtract(const Duration(days: 365));
                    final maxDate = expDate ?? DateTime.now().add(const Duration(days: 365));
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: openDate ?? (mfdDate != null ? minDate : DateTime.now()),
                      firstDate: minDate,
                      lastDate: maxDate,
                    );
                    if (picked != null) {
                      setDialogState(() => openDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_open, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Open Date (Optional)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              Text(
                                openDate != null ? _formatDate(openDate!) : 'Select date',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: openDate != null ? Colors.black87 : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (openDate != null)
                          InkWell(
                            onTap: () => setDialogState(() => openDate = null),
                            child: Icon(Icons.clear, color: Colors.grey[400], size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // Validate required fields
                setDialogState(() => errorMessage = null);
                
                if (batchController.text.trim().isEmpty) {
                  setDialogState(() => errorMessage = 'Batch number is required');
                  return;
                }
                if (mfdDate == null) {
                  setDialogState(() => errorMessage = 'Manufacturing date is required');
                  return;
                }
                if (expDate == null) {
                  setDialogState(() => errorMessage = 'Expiry date is required');
                  return;
                }
                if (expDate!.isBefore(mfdDate!) || expDate!.isAtSameMomentAs(mfdDate!)) {
                  setDialogState(() => errorMessage = 'Expiry date must be after manufacturing date');
                  return;
                }
                if (openDate != null && (openDate!.isBefore(mfdDate!) || openDate!.isAtSameMomentAs(mfdDate!))) {
                  setDialogState(() => errorMessage = 'Open date must be after manufacturing date');
                  return;
                }
                
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      setState(() {
        _cartItems[index].batchNo = batchController.text.trim();
        _cartItems[index].manufacturingDate = mfdDate;
        _cartItems[index].expiryDate = expDate;
        _cartItems[index].openDate = openDate;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isBatchInfoComplete(InwardCartItem item) {
    return item.batchNo != null && 
           item.batchNo!.trim().isNotEmpty && 
           item.manufacturingDate != null && 
           item.expiryDate != null;
  }

  String _getBatchDisplayText(InwardCartItem item) {
    if (_isBatchInfoComplete(item)) {
      return '${item.batchNo} • MFD: ${_formatDate(item.manufacturingDate!)} • EXP: ${_formatDate(item.expiryDate!)}';
    } else {
      return 'Add Required Batch Info';
    }
  }

  double get subTotal => _cartItems.fold(0, (sum, item) => sum + item.taxableAmount);
  double get totalDiscount => _cartItems.fold(0, (sum, item) => sum + item.discountAmount);
  double get totalTax => _cartItems.fold(0, (sum, item) => sum + item.taxAmount);
  double get grandTotal => _cartItems.fold(0, (sum, item) => sum + item.totalCost);

  Future<void> _saveInward() async {
    if (_selectedSupplier == null) {
      _showError('Please select a supplier');
      return;
    }
    if (_cartItems.isEmpty) {
      _showError('Please add at least one item');
      return;
    }

    // Validate batch information for all items
    for (int i = 0; i < _cartItems.length; i++) {
      final item = _cartItems[i];
      if (item.batchNo == null || item.batchNo!.trim().isEmpty) {
        _showError('Please add batch number for ${item.product.productName}');
        return;
      }
      if (item.manufacturingDate == null) {
        _showError('Please add manufacturing date for ${item.product.productName}');
        return;
      }
      if (item.expiryDate == null) {
        _showError('Please add expiry date for ${item.product.productName}');
        return;
      }
      // Validate that expiry date is after manufacturing date
      if (item.expiryDate!.isBefore(item.manufacturingDate!) || item.expiryDate!.isAtSameMomentAs(item.manufacturingDate!)) {
        _showError('Expiry date must be after manufacturing date for ${item.product.productName}');
        return;
      }
      // Validate that open date (if provided) is after manufacturing date
      if (item.openDate != null && (item.openDate!.isBefore(item.manufacturingDate!) || item.openDate!.isAtSameMomentAs(item.manufacturingDate!))) {
        _showError('Open date must be after manufacturing date for ${item.product.productName}');
        return;
      }
    }

    if (widget.storeId == null || widget.userId == null) return;

    // Check for duplicate invoice from same supplier
    final invoiceNo = _invoiceController.text.trim();
    if (invoiceNo.isNotEmpty) {
      final isDuplicate = await widget.inwardService.checkDuplicateInvoice(
        widget.storeId!,
        _selectedSupplier!.id,
        invoiceNo,
      );
      if (isDuplicate) {
        _showError('Invoice "$invoiceNo" already exists for this supplier');
        return;
      }
    }

    setState(() => _isSaving = true);

    final grnNumber = await widget.inwardService.generateGrnNumber(widget.storeId!);
    
    final result = await widget.inwardService.createInward(
      storeId: widget.storeId!,
      supplierId: _selectedSupplier!.id,
      grnNumber: grnNumber,
      supplierInvoiceNo: invoiceNo.isEmpty ? null : invoiceNo,
      receivedDate: DateTime.now(),
      subTotal: subTotal,
      discountAmount: totalDiscount,
      taxAmount: totalTax,
      totalAmount: grandTotal,
      receivedBy: widget.userId!,
      items: _cartItems,
    );

    setState(() => _isSaving = false);

    if (result != null) {
      _showSuccess('GRN $result created successfully!');
      // Clear form only after successful save
      _clearForm();
    } else {
      _showError('Failed to create GRN');
    }
  }

  void _clearForm() {
    setState(() {
      _cartItems.clear();
      _selectedSupplier = null;
      _invoiceController.clear();
      _searchController.clear();
      _products.clear();
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Panel - Supplier & Product Selection
          Expanded(
            flex: 5,
            child: Column(
              children: [
                // Supplier Selection Card
                _buildSupplierCard(),
                const SizedBox(height: 16),
                // Product Search & List
                Expanded(child: _buildProductCard()),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Right Panel - Cart & Summary
          SizedBox(
            width: 420,
            child: _buildCartCard(),
          ),
        ],
      ),
    );
  }


  Widget _buildSupplierCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_shipping, color: Colors.orange[600], size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Supplier Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              // Refresh button
              IconButton(
                onPressed: _isLoadingSuppliers ? null : _loadSuppliers,
                icon: _isLoadingSuppliers 
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange[600]))
                    : Icon(Icons.refresh, color: Colors.orange[600], size: 20),
                tooltip: 'Refresh Suppliers',
              ),
              // Supplier count badge
              if (_suppliers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(12)),
                  child: Text('${_suppliers.length} suppliers', style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Supplier Dropdown with Search
              Expanded(
                flex: 3,
                child: CompositedTransformTarget(
                  link: _supplierLayerLink,
                  child: _isLoadingSuppliers
                      ? Container(
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                        )
                      : InkWell(
                          onTap: () {
                            if (_showSupplierDropdown) {
                              _removeSupplierOverlay();
                            } else {
                              _filteredSuppliers = _suppliers;
                              _showSupplierDropdownOverlay();
                            }
                          },
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _showSupplierDropdown ? Colors.orange[600]! : Colors.grey[300]!, width: _showSupplierDropdown ? 2 : 1),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.business, color: Colors.grey[600], size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _selectedSupplier == null
                                      ? Text('Choose Supplier', style: TextStyle(color: Colors.grey[500], fontSize: 14))
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_selectedSupplier!.supplierName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                                            Text(_selectedSupplier!.supplierCode, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                          ],
                                        ),
                                ),
                                if (_selectedSupplier != null)
                                  InkWell(
                                    onTap: () => setState(() => _selectedSupplier = null),
                                    child: Icon(Icons.clear, color: Colors.grey[400], size: 18),
                                  ),
                                const SizedBox(width: 4),
                                Icon(_showSupplierDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.grey[600]),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // Invoice Number
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _invoiceController,
                  decoration: InputDecoration(
                    labelText: 'Invoice No (Optional)',
                    hintText: 'Supplier invoice',
                    prefixIcon: Icon(Icons.receipt_long, color: Colors.grey[600]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange[600]!, width: 2)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
              ),
            ],
          ),
          // Supplier Info Badge
          if (_selectedSupplier != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedSupplier!.supplierName, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[800])),
                        if (_selectedSupplier!.phone != null || _selectedSupplier!.gstNumber != null)
                          Text(
                            [if (_selectedSupplier!.phone != null) _selectedSupplier!.phone!, if (_selectedSupplier!.gstNumber != null) 'GST: ${_selectedSupplier!.gstNumber}'].join(' • '),
                            style: TextStyle(fontSize: 12, color: Colors.green[700]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Search Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory, color: Colors.blue[600], size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('Add Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    // Add New Product Button
                    TextButton.icon(
                      onPressed: () => _showAddProductDialog(),
                      icon: Icon(Icons.add, color: Colors.green[600], size: 18),
                      label: Text('New Product', style: TextStyle(color: Colors.green[600], fontSize: 13)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.green[50],
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_products.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(12)),
                        child: Text('${_products.length} found', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w500)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by product name, code or barcode...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey[400]),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _products.clear());
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: (value) {
                    if (value.length >= 2) {
                      _loadProducts(value);
                    } else if (value.isEmpty) {
                      setState(() => _products.clear());
                    }
                  },
                ),
              ],
            ),
          ),
          // Product List
          Expanded(
            child: _isLoadingProducts
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.length >= 2 
                                  ? 'No products found for "${_searchController.text}"' 
                                  : 'Search products to add',
                              style: TextStyle(color: Colors.grey[500], fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            if (_searchController.text.length >= 2) ...[
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () => _showAddProductDialog(prefillName: _searchController.text),
                                icon: Icon(Icons.add_circle, color: Colors.green[600]),
                                label: Text('Add "${_searchController.text}" as new product', style: TextStyle(color: Colors.green[600])),
                              ),
                            ] else
                              Text('Type at least 2 characters', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildProductTile(_products[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProductDialog({String? prefillName}) async {
    final nameController = TextEditingController(text: prefillName);
    final codeController = TextEditingController();
    final costController = TextEditingController();
    final sellingController = TextEditingController();
    final taxController = TextEditingController(text: '5');
    final hsnController = TextEditingController();
    final minStockController = TextEditingController(text: '10');
    final maxStockController = TextEditingController(text: '1000');
    final reorderController = TextEditingController(text: '20');
    final shelfLifeController = TextEditingController();
    final storageController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedUom = 'PCS';
    bool isVeg = true;
    bool isCombo = false;
    bool isPerishable = false;
    bool isSaving = false;
    String? errorMessage;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_box, color: Colors.green[600]),
              const SizedBox(width: 10),
              const Text('Add New Product'),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 600,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error message
                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[600], size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(errorMessage!, style: TextStyle(color: Colors.red[700], fontSize: 13))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Basic Information
                    const Text('Basic Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    // Product Name
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Product Name *',
                        hintText: 'Enter product name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.inventory_2),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: codeController,
                            decoration: InputDecoration(
                              labelText: 'Product Code *',
                              hintText: 'e.g., PROD001',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.qr_code),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              UpperCaseTextFormatter(), // Custom formatter to show uppercase as user types
                            ],
                            onChanged: (value) async {
                              // Real-time duplicate checking
                              if (value.trim().length >= 3) {
                                final isDuplicate = await widget.inwardService.checkDuplicateProductCode(
                                  widget.orgId!,
                                  value.trim().toUpperCase(),
                                );
                                if (isDuplicate) {
                                  setDialogState(() {
                                    errorMessage = 'Product code "${value.toUpperCase()}" already exists';
                                  });
                                } else {
                                  setDialogState(() {
                                    errorMessage = null;
                                  });
                                }
                              }
                            },
                            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: hsnController,
                            decoration: InputDecoration(
                              labelText: 'HSN Code *',
                              hintText: 'Enter HSN code',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.numbers),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // UOM and Tax Row
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedUom,
                            decoration: InputDecoration(
                              labelText: 'Unit of Measure *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.straighten),
                            ),
                            items: ['PCS', 'KG', 'GM', 'LTR', 'ML', 'BOX', 'PKT', 'DOZEN']
                                .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                .toList(),
                            onChanged: (v) => setDialogState(() => selectedUom = v ?? 'PCS'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: taxController,
                            decoration: InputDecoration(
                              labelText: 'Tax Rate (%) *',
                              suffixText: '%',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.percent),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Cost & Selling Price Row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: costController,
                            decoration: InputDecoration(
                              labelText: 'Cost Price *',
                              hintText: 'Enter cost price',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) => v == null || v.trim().isEmpty || double.tryParse(v) == null ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: sellingController,
                            decoration: InputDecoration(
                              labelText: 'Selling Price *',
                              hintText: 'Enter selling price',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) => v == null || v.trim().isEmpty || double.tryParse(v) == null ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Product Properties
                    const Text('Product Properties', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    // Checkboxes Row
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            title: const Text('Vegetarian *', style: TextStyle(fontSize: 14)),
                            value: isVeg,
                            onChanged: (v) => setDialogState(() => isVeg = v ?? true),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            title: const Text('Combo Item *', style: TextStyle(fontSize: 14)),
                            value: isCombo,
                            onChanged: (v) => setDialogState(() => isCombo = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      title: const Text('Perishable Item', style: TextStyle(fontSize: 14)),
                      value: isPerishable,
                      onChanged: (v) => setDialogState(() => isPerishable = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 16),
                    // Stock Management
                    const Text('Stock Management', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minStockController,
                            decoration: InputDecoration(
                              labelText: 'Min Stock Level *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.trending_down),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: maxStockController,
                            decoration: InputDecoration(
                              labelText: 'Max Stock Level *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.trending_up),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: reorderController,
                            decoration: InputDecoration(
                              labelText: 'Reorder Level *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.refresh),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Perishable Details (only if perishable is checked)
                    if (isPerishable) ...[
                      const Text('Perishable Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: shelfLifeController,
                              decoration: InputDecoration(
                                labelText: 'Shelf Life (Days)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.schedule),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: storageController,
                              decoration: InputDecoration(
                                labelText: 'Storage Instructions',
                                hintText: 'e.g., Keep refrigerated',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.storage),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving ? null : () async {
                if (formKey.currentState!.validate()) {
                  setDialogState(() {
                    isSaving = true;
                    errorMessage = null;
                  });
                  
                  // Check for duplicate product code first
                  final isDuplicate = await widget.inwardService.checkDuplicateProductCode(
                    widget.orgId!,
                    codeController.text.trim(),
                  );
                  
                  if (isDuplicate) {
                    setDialogState(() {
                      isSaving = false;
                      errorMessage = 'Product code "${codeController.text.trim()}" already exists';
                    });
                    return;
                  }
                  
                  // Create product with all details
                  final success = await widget.inwardService.createProductWithDetails(
                    orgId: widget.orgId!,
                    productCode: codeController.text.trim(),
                    productName: nameController.text.trim(),
                    hsnCode: hsnController.text.trim(),
                    uom: selectedUom,
                    costPrice: double.tryParse(costController.text) ?? 0,
                    sellingPrice: double.tryParse(sellingController.text) ?? 0,
                    taxPercentage: double.tryParse(taxController.text) ?? 5,
                    isVeg: isVeg,
                    isCombo: isCombo,
                    isPerishable: isPerishable,
                    minStockLevel: int.tryParse(minStockController.text) ?? 10,
                    maxStockLevel: int.tryParse(maxStockController.text) ?? 1000,
                    reorderLevel: int.tryParse(reorderController.text) ?? 20,
                    shelfLifeDays: isPerishable ? int.tryParse(shelfLifeController.text) : null,
                    storageInstructions: isPerishable && storageController.text.trim().isNotEmpty ? storageController.text.trim() : null,
                  );
                  
                  if (success) {
                    Navigator.pop(context, true);
                  } else {
                    setDialogState(() {
                      isSaving = false;
                      errorMessage = 'Failed to create product. Please try again.';
                    });
                  }
                }
              },
              icon: isSaving 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 18),
              label: Text(isSaving ? 'Saving...' : 'Save Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _showSuccess('Product added successfully!');
      // Reload products with the search term
      if (_searchController.text.isNotEmpty) {
        _loadProducts(_searchController.text);
      }
    }
  }


  Widget _buildProductTile(InwardProduct product) {
    final inCart = _cartItems.any((item) => item.product.id == product.id);
    final cartQty = _cartItems.where((item) => item.product.id == product.id).fold(0.0, (sum, item) => sum + item.quantity);
    
    return Material(
      color: inCart ? Colors.orange[50] : Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _addToCart(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Product Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: inCart ? Colors.orange[100] : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: inCart ? Colors.orange[300]! : Colors.grey[200]!),
                ),
                child: Center(
                  child: Text(
                    product.productName[0].toUpperCase(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: inCart ? Colors.orange[700] : Colors.grey[600]),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '${product.productCode} • ${product.uom}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Cost & Add Button
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${product.costPrice.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  const SizedBox(height: 4),
                  if (inCart)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Colors.orange[600], borderRadius: BorderRadius.circular(12)),
                      child: Text('×${cartQty.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Colors.blue[600], borderRadius: BorderRadius.circular(12)),
                      child: const Text('+ Add', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Cart Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange[600],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text('Cart (${_cartItems.length} items)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                if (_cartItems.isNotEmpty)
                  InkWell(
                    onTap: _clearForm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.clear_all, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Clear', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Cart Items
          Expanded(
            child: _cartItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_shopping_cart, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No items in cart', style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('Search and add products', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _cartScrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _cartItems.length,
                    itemBuilder: (context, index) => _buildCartItem(index),
                  ),
          ),
          // Summary & Save
          _buildCartSummary(),
        ],
      ),
    );
  }

  Widget _buildCartItem(int index) {
    final item = _cartItems[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Name & Delete
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.product.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(item.product.productCode, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _removeFromCart(index),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.delete_outline, color: Colors.red[400], size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Qty, Cost, Discount Row
          Row(
            children: [
              _buildMiniInput('Qty', item.quantity.toStringAsFixed(0), (v) => _updateCartItem(index, quantity: double.tryParse(v) ?? 1), isNumber: true),
              const SizedBox(width: 10),
              _buildMiniInput('Cost ₹', item.unitCost.toStringAsFixed(2), (v) => _updateCartItem(index, unitCost: double.tryParse(v) ?? 0), isDecimal: true),
              const SizedBox(width: 10),
              _buildMiniInput('Disc %', item.discountPercentage.toStringAsFixed(0), (v) => _updateCartItem(index, discount: double.tryParse(v) ?? 0), isNumber: true),
            ],
          ),
          const SizedBox(height: 12),
          // Batch Information Row
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showBatchDialog(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isBatchInfoComplete(item) ? Colors.blue[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _isBatchInfoComplete(item) ? Colors.blue[200]! : Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isBatchInfoComplete(item) ? Icons.check_circle : Icons.warning,
                          size: 16,
                          color: _isBatchInfoComplete(item) ? Colors.blue[600] : Colors.red[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _getBatchDisplayText(item),
                            style: TextStyle(
                              fontSize: 12,
                              color: _isBatchInfoComplete(item) ? Colors.blue[700] : Colors.red[700],
                              fontWeight: _isBatchInfoComplete(item) ? FontWeight.w500 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.edit,
                          size: 14,
                          color: _isBatchInfoComplete(item) ? Colors.blue[600] : Colors.red[600],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Line Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tax: ₹${item.taxAmount.toStringAsFixed(2)} (${item.taxPercentage}%)', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              Text('₹${item.totalCost.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange[700])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInput(String label, String value, Function(String) onChanged, {bool isNumber = false, bool isDecimal = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: TextField(
              controller: TextEditingController(text: value),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.orange[400]!)),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 13),
              keyboardType: isDecimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
              inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCartSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          // Summary Rows
          _buildSummaryRow('Sub Total', '₹${subTotal.toStringAsFixed(2)}'),
          const SizedBox(height: 6),
          _buildSummaryRow('Discount', '-₹${totalDiscount.toStringAsFixed(2)}', isNegative: true),
          const SizedBox(height: 6),
          _buildSummaryRow('Tax (GST)', '₹${totalTax.toStringAsFixed(2)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          // Grand Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Grand Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('₹${grandTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange[700])),
            ],
          ),
          const SizedBox(height: 16),
          // Save Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving || _cartItems.isEmpty || _selectedSupplier == null ? null : _saveInward,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 20),
                        SizedBox(width: 8),
                        Text('Save & Post GRN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isNegative = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: isNegative ? Colors.red[400] : Colors.grey[800])),
      ],
    );
  }
}


// ============ INWARD HISTORY TAB ============
class _InwardHistoryTab extends StatefulWidget {
  final String? storeId;
  final InwardService inwardService;

  const _InwardHistoryTab({
    required this.storeId,
    required this.inwardService,
  });

  @override
  State<_InwardHistoryTab> createState() => _InwardHistoryTabState();
}

class _InwardHistoryTabState extends State<_InwardHistoryTab> {
  List<InwardHeader> _inwards = [];
  InwardSummary _summary = InwardSummary();
  bool _isLoading = true;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    // Set default date range to last 7 days
    final now = DateTime.now();
    _toDate = now;
    _fromDate = DateTime(now.year, now.month, now.day - 7);
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.storeId == null) return;
    setState(() => _isLoading = true);

    final inwards = await widget.inwardService.getInwardList(widget.storeId!, fromDate: _fromDate, toDate: _toDate);
    final summary = await widget.inwardService.getInwardSummary(widget.storeId!, fromDate: _fromDate, toDate: _toDate);

    setState(() {
      _inwards = inwards;
      _summary = summary;
      _isLoading = false;
    });
  }

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now().subtract(const Duration(days: 180)), // Allow up to 6 months for CSV export
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      _loadData();
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
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Summary Cards Row
          _buildSummaryRow(),
          const SizedBox(height: 20),
          // History Table
          Expanded(child: _buildHistoryCard()),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        _buildStatCard('Total GRNs', '${_summary.totalCount}', Icons.receipt_long, Colors.blue),
        const SizedBox(width: 16),
        _buildStatCard('Total Value', '₹${_formatAmount(_summary.totalAmount)}', Icons.account_balance_wallet, Colors.green),
        const SizedBox(width: 16),
        _buildStatCard('Posted', '${_summary.postedCount}', Icons.check_circle, Colors.teal),
        const SizedBox(width: 16),
        _buildStatCard('Draft', '${_summary.draftCount}', Icons.edit_note, Colors.orange),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header with Date Filter
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.history, color: Colors.purple[600], size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('GRN History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    // Export CSV Button
                    InwardCsvExportButton(
                      storeId: widget.storeId,
                      inwards: _inwards,
                      inwardService: widget.inwardService,
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _loadData,
                      icon: Icon(Icons.refresh, color: Colors.grey[600]),
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Date Range Filters (matching write-off screen design)
                Row(
                  children: [
                    const Icon(Icons.filter_list, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text(
                      'Filter GRNs',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                if (_inwards.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Found ${_inwards.length} GRN records',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: Colors.grey[50],
            child: Row(
              children: [
                _tableHeader('GRN Number', flex: 2),
                _tableHeader('Supplier', flex: 2),
                _tableHeader('Date', flex: 2),
                _tableHeader('Amount', flex: 2),
                _tableHeader('Created By', flex: 2),
                _tableHeader('Status', flex: 1),
                _tableHeader('', flex: 1),
              ],
            ),
          ),
          // Table Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _inwards.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No GRN records found', style: TextStyle(color: Colors.grey[500])),
                            const SizedBox(height: 4),
                            Text('Try changing the date range', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _inwards.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                        itemBuilder: (context, index) => _buildHistoryRow(_inwards[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: 13)),
    );
  }

  Widget _buildHistoryRow(InwardHeader inward) {
    return InkWell(
      onTap: () => _showInwardDetails(inward.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(inward.grnNumber, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Text(inward.supplierName ?? '-', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Text(_formatDate(inward.receivedDate), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Text('₹${inward.totalAmount.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[700], fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      inward.receivedByName ?? '-',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: inward.status == 'posted' ? Colors.green[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  inward.status.toUpperCase(),
                  style: TextStyle(fontSize: 11, color: inward.status == 'posted' ? Colors.green[700] : Colors.orange[700], fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Center(
                child: IconButton(
                  icon: Icon(Icons.visibility_outlined, color: Colors.blue[600], size: 20),
                  onPressed: () => _showInwardDetails(inward.id),
                  tooltip: 'View Details',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInwardDetails(String inwardId) async {
    final details = await widget.inwardService.getInwardDetails(inwardId);
    if (details == null || !mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 650,
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange[600],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(details.grnNumber, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info Grid
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            _infoColumn('Supplier', details.supplierName ?? '-'),
                            _infoColumn('Date', _formatDate(details.receivedDate)),
                            _infoColumn('Invoice No', details.supplierInvoiceNo ?? '-'),
                            _infoColumn('Received By', details.receivedByName ?? '-'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Items', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 12),
                      // Items List
                      ...details.items.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[200]!),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(item.productCode ?? '-', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                ],
                              ),
                            ),
                            Expanded(child: Text('${item.quantity} ${item.uom}', style: TextStyle(color: Colors.grey[700]))),
                            Expanded(child: Text('₹${item.unitCost.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey[700]))),
                            Expanded(child: Text('₹${item.totalCost.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                          ],
                        ),
                      )),
                      const Divider(height: 32),
                      // Totals
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _totalRow('Sub Total', '₹${details.subTotal.toStringAsFixed(2)}'),
                              _totalRow('Discount', '-₹${details.discountAmount.toStringAsFixed(2)}'),
                              _totalRow('Tax', '₹${details.taxAmount.toStringAsFixed(2)}'),
                              const SizedBox(height: 8),
                              Text('Total: ₹${details.totalAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoColumn(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.grey[600]))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}
