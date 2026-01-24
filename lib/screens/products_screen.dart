import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../providers/auth_provider.dart';
import '../services/product_service.dart';
import '../services/inward_service.dart';
import '../services/image_helper.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';
import '../widgets/raw_materials_quantity_selector.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final ProductService _productService = ProductService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Item> _products = [];
  List<ItemCategory> _categories = [];
  String? _selectedCategoryId;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _orgId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  Future<void> _initializeData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _orgId = authProvider.userProfile?.organizationId;
    
    if (_orgId == null) {
      _showError('Organization not found');
      return;
    }

    await Future.wait([
      _loadCategories(),
      _loadProducts(refresh: true),
    ]);
  }

  Future<void> _loadCategories() async {
    if (_orgId == null) return;
    final categories = await _productService.getCategories(_orgId!);
    if (mounted) {
      setState(() => _categories = categories);
    }
  }

  Future<void> _loadProducts({bool refresh = false}) async {
    if (_orgId == null || _isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _currentPage = 1;
        _products = [];
      }
    });

    final response = await _productService.getProducts(
      orgId: _orgId!,
      page: _currentPage,
      searchQuery: _searchController.text.isEmpty ? null : _searchController.text,
      categoryId: _selectedCategoryId,
    );

    if (mounted) {
      setState(() {
        _products = response.items;
        _totalPages = response.totalPages;
        _totalCount = response.totalCount;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || _currentPage >= _totalPages || _orgId == null) return;

    setState(() => _isLoadingMore = true);

    final response = await _productService.getProducts(
      orgId: _orgId!,
      page: _currentPage + 1,
      searchQuery: _searchController.text.isEmpty ? null : _searchController.text,
      categoryId: _selectedCategoryId,
    );

    if (mounted) {
      setState(() {
        _products.addAll(response.items);
        _currentPage = response.currentPage;
        _isLoadingMore = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_searchController.text == value) {
        _loadProducts(refresh: true);
      }
    });
  }

  void _onCategoryChanged(String? categoryId) {
    setState(() => _selectedCategoryId = categoryId);
    _loadProducts(refresh: true);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _showAddProductDialog() async {
    if (_orgId == null) {
      _showError('Organization not found');
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddProductDialog(orgId: _orgId!),
    );

    if (result == true) {
      // Refresh products list after adding new product
      await _loadProducts(refresh: true);
    }
  }

  Future<void> _showEditOptionsDialog(Item product) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.edit, color: Colors.orange[600]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Product',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          product.itemName,
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Options
              Column(
                children: [
                  // Basic Details Option
                  InkWell(
                    onTap: () => Navigator.pop(context, 'basic'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.edit_note, color: Colors.blue[600]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Basic Details',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                ),
                                Text(
                                  'Edit name, price, image & raw materials',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // All Details Option
                  InkWell(
                    onTap: () => Navigator.pop(context, 'all'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.settings, color: Colors.green[600]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'All Details',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                ),
                                Text(
                                  'Edit all product information & settings',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      if (result == 'basic') {
        _editProductBasic(product);
      } else if (result == 'all') {
        _editProductAll(product);
      }
    }
  }

  Future<void> _editProductBasic(Item product) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ProductEditDialog(
        product: product,
        orgId: _orgId!,
        productService: _productService,
      ),
    );

    if (result == true) {
      _showSuccess('Product updated successfully');
      _loadProducts(refresh: true);
    }
  }

  Future<void> _editProductAll(Item product) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditProductAllDetailsDialog(
        product: product,
        orgId: _orgId!,
      ),
    );

    if (result == true) {
      _showSuccess('Product updated successfully');
      _loadProducts(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Single header with back button and window controls
          _buildHeader(context),
          // Filters
          _buildFilters(),
          // Product count
          _buildProductCount(),
          // Product grid
          Expanded(child: _buildProductGrid()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProductDialog,
        backgroundColor: Colors.orange[600],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
                    child: const Icon(Icons.inventory, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Products',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadProducts(refresh: true),
            tooltip: 'Refresh',
          ),
          // Debug button
          const DebugButton(),
          // Window controls
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Stack vertically on smaller screens
          if (constraints.maxWidth < 600) {
            return Column(
              children: [
                _buildSearchField(),
                const SizedBox(height: 12),
                _buildCategorySelector(),
              ],
            );
          }
          // Side by side on larger screens
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildSearchField()),
              const SizedBox(width: 16),
              Expanded(child: _buildCategorySelector()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search products...',
          prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                  onPressed: () {
                    _searchController.clear();
                    _loadProducts(refresh: true);
                  },
                )
              : null,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildCategorySelector() {
    final selectedCategory = _categories.where((c) => c.id == _selectedCategoryId).firstOrNull;
    final displayText = selectedCategory?.categoryName ?? 'All Categories';

    return SizedBox(
      height: 48,
      child: InkWell(
        onTap: () => _showCategoryMenu(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[400]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.category_outlined, color: Colors.grey[600], size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  displayText,
                  style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryMenu() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    
    showMenu<String?>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset(button.size.width - 250, 130), ancestor: overlay),
          button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 220, maxHeight: 400),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem<String?>(
          value: 'all',
          child: Row(
            children: [
              Icon(
                _selectedCategoryId == null ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: _selectedCategoryId == null ? Colors.orange[600] : Colors.grey[400],
              ),
              const SizedBox(width: 12),
              const Text('All Categories'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ..._categories.map((cat) => PopupMenuItem<String?>(
          value: cat.id,
          child: Row(
            children: [
              Icon(
                _selectedCategoryId == cat.id ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: _selectedCategoryId == cat.id ? Colors.orange[600] : Colors.grey[400],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cat.categoryName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        )),
      ],
    ).then((value) {
      if (value != null) {
        if (value == 'all') {
          _onCategoryChanged(null);
        } else {
          _onCategoryChanged(value);
        }
      }
    });
  }

  Widget _buildProductCount() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$_totalCount products found',
            style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500),
          ),
          Text(
            'Page $_currentPage of $_totalPages',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading && _products.isEmpty) {
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
              'No products found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadProducts(refresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 1200
              ? 5
              : constraints.maxWidth > 900
                  ? 4
                  : constraints.maxWidth > 600
                      ? 3
                      : 2;

          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _products.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _products.length) {
                return const Center(child: CircularProgressIndicator());
              }
              return _buildProductCard(_products[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Item product) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEditOptionsDialog(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: _buildProductImage(product),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.itemName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.itemCode,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${product.sellingPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.orange[600],
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
    );
  }

  Widget _buildProductImage(Item product) {
    if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: product.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => _buildPlaceholderImage(),
      );
    }
    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.fastfood,
        size: 48,
        color: Colors.grey[400],
      ),
    );
  }
}


class ProductEditDialog extends StatefulWidget {
  final Item product;
  final String orgId;
  final ProductService productService;

  const ProductEditDialog({
    super.key,
    required this.product,
    required this.orgId,
    required this.productService,
  });

  @override
  State<ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<ProductEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  final ImageHelper _imageHelper = ImageHelper();
  
  String? _currentImageUrl;
  Uint8List? _newImageBytes;
  String? _newImageName;
  bool _isSaving = false;
  bool _imageRemoved = false;
  List<RawMaterialMapping> _selectedRawMaterialMappings = [];
  int? _totalPiecesLimit;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.itemName);
    _priceController = TextEditingController(
      text: widget.product.sellingPrice.toStringAsFixed(2),
    );
    _currentImageUrl = widget.product.imageUrl;
    _selectedRawMaterialMappings = List.from(widget.product.rawMaterialMapping ?? []);
    _totalPiecesLimit = widget.product.totalPiecesLimit;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await _imageHelper.pickAndCropImage(context);

      if (result != null) {
        setState(() {
          _newImageBytes = result.bytes;
          _newImageName = result.fileName;
          _imageRemoved = false;
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  void _removeImage() {
    setState(() {
      _newImageBytes = null;
      _newImageName = null;
      _imageRemoved = true;
    });
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    debugPrint('💾 PRODUCT_EDIT: Starting save process...');
    debugPrint('💾 PRODUCT_EDIT: Product ID: ${widget.product.id}');
    debugPrint('💾 PRODUCT_EDIT: Product Name: ${_nameController.text.trim()}');
    debugPrint('💾 PRODUCT_EDIT: Org ID: ${widget.orgId}');
    debugPrint('💾 PRODUCT_EDIT: Raw material mappings count: ${_selectedRawMaterialMappings.length}');
    
    for (int i = 0; i < _selectedRawMaterialMappings.length; i++) {
      final mapping = _selectedRawMaterialMappings[i];
      debugPrint('💾 PRODUCT_EDIT: Mapping $i: ${mapping.materialName} - ${mapping.quantity} ${mapping.uom}');
    }

    setState(() => _isSaving = true);

    try {
      String? imageUrl = _currentImageUrl;

      // Upload new image if selected
      if (_newImageBytes != null && _newImageName != null) {
        debugPrint('💾 PRODUCT_EDIT: Uploading new image...');
        imageUrl = await widget.productService.uploadProductImage(
          orgId: widget.orgId,
          productId: widget.product.id,
          imageBytes: _newImageBytes!,
          fileName: _newImageName!,
        );

        if (imageUrl == null) {
          debugPrint('❌ PRODUCT_EDIT: Image upload failed');
          _showError('Failed to upload image');
          setState(() => _isSaving = false);
          return;
        }
        debugPrint('✅ PRODUCT_EDIT: Image uploaded successfully');
      } else if (_imageRemoved) {
        debugPrint('💾 PRODUCT_EDIT: Removing existing image...');
        // Remove image if user cleared it
        if (_currentImageUrl != null) {
          await widget.productService.deleteProductImage(
            orgId: widget.orgId,
            productId: widget.product.id,
            currentImageUrl: _currentImageUrl!,
          );
        }
        imageUrl = null;
        debugPrint('✅ PRODUCT_EDIT: Image removed successfully');
      }

      // Prepare raw material mapping data
      final rawMaterialMappingData = _selectedRawMaterialMappings.map((m) => m.toJson()).toList();
      debugPrint('💾 PRODUCT_EDIT: Raw material mapping JSON: $rawMaterialMappingData');

      // Update product
      debugPrint('💾 PRODUCT_EDIT: Calling updateProduct...');
      final success = await widget.productService.updateProduct(
        productId: widget.product.id,
        orgId: widget.orgId,
        itemName: _nameController.text.trim(),
        sellingPrice: double.parse(_priceController.text),
        imageUrl: _imageRemoved ? '' : imageUrl,
        rawMaterialMapping: rawMaterialMappingData,
        totalPiecesLimit: _totalPiecesLimit,
      );

      debugPrint('💾 PRODUCT_EDIT: Update result: $success');

      if (success) {
        debugPrint('✅ PRODUCT_EDIT: Product updated successfully, closing dialog');
        if (mounted) Navigator.of(context).pop(true);
      } else {
        debugPrint('❌ PRODUCT_EDIT: Product update failed');
        _showError('Failed to update product');
      }
    } catch (e) {
      debugPrint('❌ PRODUCT_EDIT: Exception during save: $e');
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildImageSection(),
                      const SizedBox(height: 24),
                      _buildNameField(),
                      const SizedBox(height: 16),
                      _buildPriceField(),
                      const SizedBox(height: 16),
                      _buildPiecesLimitField(),
                      const SizedBox(height: 16),
                      _buildRawMaterialsSection(),
                      const SizedBox(height: 8),
                      _buildProductInfo(),
                    ],
                  ),
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[600],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Edit Product',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Product Image',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Center(
          child: Stack(
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildImagePreview(),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasImage())
                      _buildImageButton(
                        icon: Icons.delete,
                        color: Colors.red,
                        onTap: _removeImage,
                      ),
                    const SizedBox(width: 4),
                    _buildImageButton(
                      icon: Icons.camera_alt,
                      color: Colors.orange[600]!,
                      onTap: _pickImage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _hasImage() {
    return _newImageBytes != null || 
           (_currentImageUrl != null && !_imageRemoved);
  }

  Widget _buildImagePreview() {
    if (_newImageBytes != null) {
      return Image.memory(_newImageBytes!, fit: BoxFit.cover);
    }
    
    if (_currentImageUrl != null && !_imageRemoved) {
      return CachedNetworkImage(
        imageUrl: _currentImageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text(
          'Add Image',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildImageButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'Product Name',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.label),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter product name';
        }
        return null;
      },
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      decoration: InputDecoration(
        labelText: 'Selling Price',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.currency_rupee),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter price';
        }
        final price = double.tryParse(value);
        if (price == null || price <= 0) {
          return 'Please enter a valid price';
        }
        return null;
      },
    );
  }

  Widget _buildPiecesLimitField() {
    return TextFormField(
      initialValue: _totalPiecesLimit?.toString() ?? '',
      decoration: InputDecoration(
        labelText: 'Total Pieces Limit (Optional)',
        hintText: 'e.g., 8 for Chicken Bucket - 8 Pcs',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.numbers),
        helperText: 'Maximum total pieces that can be mapped to raw materials',
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        setState(() {
          _totalPiecesLimit = value.isEmpty ? null : int.tryParse(value);
        });
      },
    );
  }

  Widget _buildRawMaterialsSection() {
    return RawMaterialsQuantitySelector(
      orgId: widget.orgId,
      selectedMappings: _selectedRawMaterialMappings,
      totalPiecesLimit: _totalPiecesLimit,
      onMappingChanged: (mappings) {
        setState(() {
          _selectedRawMaterialMappings = mappings;
        });
      },
    );
  }

  Widget _buildProductInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Code', widget.product.itemCode),
          if (widget.product.category != null)
            _buildInfoRow('Category', widget.product.category!.categoryName),
          if (widget.product.unit != null)
            _buildInfoRow('Unit', widget.product.unit!),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isSaving ? null : _saveProduct,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
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
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

class AddProductDialog extends StatefulWidget {
  final String orgId;

  const AddProductDialog({
    super.key,
    required this.orgId,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _costController = TextEditingController();
  final _sellingController = TextEditingController();
  final _taxController = TextEditingController(text: '5');
  final _hsnController = TextEditingController();
  final _minStockController = TextEditingController(text: '10');
  final _maxStockController = TextEditingController(text: '1000');
  final _reorderController = TextEditingController(text: '20');
  
  String _selectedUom = 'PCS';
  bool _isVeg = true;
  bool _isCombo = false;
  bool _isSaving = false;
  String? _errorMessage;

  final List<String> _uomOptions = ['PCS', 'KG', 'GRAM', 'LITER', 'ML', 'METER', 'BOX', 'PACKET'];

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _costController.dispose();
    _sellingController.dispose();
    _taxController.dispose();
    _hsnController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final productService = ProductService();
      
      // Check for duplicate product code
      final isDuplicate = await productService.checkDuplicateProductCode(
        widget.orgId,
        _codeController.text.trim().toUpperCase(),
      );
      
      if (isDuplicate) {
        setState(() => _errorMessage = 'Product code "${_codeController.text.trim().toUpperCase()}" already exists');
        return;
      }
      
      final success = await productService.createProduct(
        orgId: widget.orgId,
        itemCode: _codeController.text.trim().toUpperCase(),
        itemName: _nameController.text.trim(),
        shortName: _nameController.text.trim().length > 50 ? _nameController.text.trim().substring(0, 50) : null,
        description: null, // Can be added later if needed
        unit: _selectedUom,
        hsnCode: _hsnController.text.trim().isEmpty ? null : _hsnController.text.trim(),
        costPrice: double.tryParse(_costController.text) ?? 0,
        sellingPrice: double.tryParse(_sellingController.text) ?? 0,
        mrp: double.tryParse(_sellingController.text), // Use selling price as MRP by default
        taxRate: double.tryParse(_taxController.text) ?? 5.00,
        taxInclusive: true,
        minStockLevel: (double.tryParse(_minStockController.text) ?? 10).toInt(),
        maxStockLevel: (double.tryParse(_maxStockController.text) ?? 1000).toInt(),
        reorderLevel: (double.tryParse(_reorderController.text) ?? 20).toInt(),
        isCombo: _isCombo,
        isVeg: _isVeg,
        isAvailable: true,
        isActive: true,
        displayOrder: 0,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product created successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _errorMessage = 'Failed to create product. Please try again.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error creating product: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[600],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_box, color: Colors.white),
                  const SizedBox(width: 10),
                  const Text(
                    'Add New Product',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
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
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error message
                      if (_errorMessage != null) ...[
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
                              Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red[700], fontSize: 13))),
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
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Product Name *',
                          hintText: 'Enter product name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.inventory_2),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // Product Code and UOM
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _codeController,
                              decoration: InputDecoration(
                                labelText: 'Product Code *',
                                hintText: 'e.g., PROD001',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.qr_code),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              onChanged: (value) async {
                                // Real-time duplicate checking
                                if (value.trim().length >= 3) {
                                  final productService = ProductService();
                                  final isDuplicate = await productService.checkDuplicateProductCode(
                                    widget.orgId,
                                    value.trim().toUpperCase(),
                                  );
                                  if (isDuplicate) {
                                    setState(() {
                                      _errorMessage = 'Product code "${value.toUpperCase()}" already exists';
                                    });
                                  } else {
                                    setState(() {
                                      _errorMessage = null;
                                    });
                                  }
                                }
                              },
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedUom,
                              decoration: InputDecoration(
                                labelText: 'UOM *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.straighten),
                              ),
                              items: _uomOptions.map((uom) => DropdownMenuItem(value: uom, child: Text(uom))).toList(),
                              onChanged: (value) => setState(() => _selectedUom = value!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Pricing Information
                      const Text('Pricing Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _costController,
                              decoration: InputDecoration(
                                labelText: 'Cost Price *',
                                hintText: '0.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.currency_rupee),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _sellingController,
                              decoration: InputDecoration(
                                labelText: 'Selling Price *',
                                hintText: '0.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.sell),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _taxController,
                              decoration: InputDecoration(
                                labelText: 'Tax %',
                                hintText: '5.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.percent),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _hsnController,
                              decoration: InputDecoration(
                                labelText: 'HSN Code',
                                hintText: 'e.g., 1234',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.tag),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Stock Information
                      const Text('Stock Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minStockController,
                              decoration: InputDecoration(
                                labelText: 'Min Stock',
                                hintText: '10',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.inventory),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _maxStockController,
                              decoration: InputDecoration(
                                labelText: 'Max Stock',
                                hintText: '1000',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.inventory_2),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _reorderController,
                              decoration: InputDecoration(
                                labelText: 'Reorder Level',
                                hintText: '20',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.refresh),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Product Properties
                      const Text('Product Properties', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Vegetarian'),
                              value: _isVeg,
                              onChanged: (value) => setState(() => _isVeg = value!),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Combo Item'),
                              value: _isCombo,
                              onChanged: (value) => setState(() => _isCombo = value!),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create Product'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditProductAllDetailsDialog extends StatefulWidget {
  final Item product;
  final String orgId;

  const EditProductAllDetailsDialog({
    super.key,
    required this.product,
    required this.orgId,
  });

  @override
  State<EditProductAllDetailsDialog> createState() => _EditProductAllDetailsDialogState();
}

class _EditProductAllDetailsDialogState extends State<EditProductAllDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _costController;
  late TextEditingController _sellingController;
  late TextEditingController _taxController;
  late TextEditingController _hsnController;
  late TextEditingController _minStockController;
  late TextEditingController _maxStockController;
  late TextEditingController _reorderController;
  
  late String _selectedUom;
  late bool _isVeg;
  late bool _isCombo;
  bool _isSaving = false;
  String? _errorMessage;

  final List<String> _uomOptions = ['PCS', 'KG', 'GRAM', 'LITER', 'ML', 'METER', 'BOX', 'PACKET'];

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current product data
    _nameController = TextEditingController(text: widget.product.itemName);
    _costController = TextEditingController(text: widget.product.costPrice?.toStringAsFixed(2) ?? '0.00');
    _sellingController = TextEditingController(text: widget.product.sellingPrice.toStringAsFixed(2));
    _taxController = TextEditingController(text: widget.product.taxRate?.toStringAsFixed(2) ?? '5.00');
    _hsnController = TextEditingController(text: widget.product.hsnCode ?? '');
    _minStockController = TextEditingController(text: widget.product.minStockLevel?.toString() ?? '10');
    _maxStockController = TextEditingController(text: widget.product.maxStockLevel?.toString() ?? '1000');
    _reorderController = TextEditingController(text: widget.product.reorderLevel?.toString() ?? '20');
    
    _selectedUom = widget.product.unit ?? 'PCS';
    _isVeg = widget.product.isVeg ?? false;
    _isCombo = widget.product.isCombo ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _costController.dispose();
    _sellingController.dispose();
    _taxController.dispose();
    _hsnController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final productService = ProductService();
      
      // Use the comprehensive updateProduct method with all form fields
      final success = await productService.updateProduct(
        productId: widget.product.id,
        orgId: widget.orgId,
        itemName: _nameController.text.trim(),
        sellingPrice: double.tryParse(_sellingController.text) ?? 0,
        costPrice: double.tryParse(_costController.text) ?? 0,
        taxRate: double.tryParse(_taxController.text) ?? 5.00,
        hsnCode: _hsnController.text.trim().isEmpty ? null : _hsnController.text.trim(),
        minStockLevel: int.tryParse(_minStockController.text) ?? 10,
        maxStockLevel: int.tryParse(_maxStockController.text) ?? 1000,
        reorderLevel: int.tryParse(_reorderController.text) ?? 20,
        isVeg: _isVeg,
        isCombo: _isCombo,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _errorMessage = 'Failed to update product. Please try again.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error updating product: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[600],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit All Details',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.product.itemCode,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
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
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error message
                      if (_errorMessage != null) ...[
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
                              Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red[700], fontSize: 13))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Product Code (Read-only)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Text('Product Code: ', style: TextStyle(color: Colors.grey[600])),
                            Text(widget.product.itemCode, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Basic Information
                      const Text('Basic Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      // Product Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Product Name *',
                          hintText: 'Enter product name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.inventory_2),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // UOM (Read-only for existing products)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.straighten, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Text('Unit of Measure: ', style: TextStyle(color: Colors.grey[600])),
                            Text(_selectedUom, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Pricing Information
                      const Text('Pricing Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _costController,
                              decoration: InputDecoration(
                                labelText: 'Cost Price *',
                                hintText: '0.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.currency_rupee),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _sellingController,
                              decoration: InputDecoration(
                                labelText: 'Selling Price *',
                                hintText: '0.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.sell),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _taxController,
                              decoration: InputDecoration(
                                labelText: 'Tax %',
                                hintText: '5.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.percent),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _hsnController,
                              decoration: InputDecoration(
                                labelText: 'HSN Code',
                                hintText: 'e.g., 1234',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.tag),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Stock Information
                      const Text('Stock Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minStockController,
                              decoration: InputDecoration(
                                labelText: 'Min Stock',
                                hintText: '10',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.inventory),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _maxStockController,
                              decoration: InputDecoration(
                                labelText: 'Max Stock',
                                hintText: '1000',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.inventory_2),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _reorderController,
                              decoration: InputDecoration(
                                labelText: 'Reorder Level',
                                hintText: '20',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.refresh),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Product Properties
                      const Text('Product Properties', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Vegetarian'),
                              value: _isVeg,
                              onChanged: (value) => setState(() => _isVeg = value!),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Combo Item'),
                              value: _isCombo,
                              onChanged: (value) => setState(() => _isCombo = value!),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _updateProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Update Product'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}