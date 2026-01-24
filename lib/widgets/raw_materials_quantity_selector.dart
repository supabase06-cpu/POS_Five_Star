import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/item_model.dart';
import '../services/grn_service.dart';
import '../services/unit_conversion_service.dart';

class RawMaterialsQuantitySelector extends StatefulWidget {
  final String orgId;
  final List<RawMaterialMapping>? selectedMappings;
  final int? totalPiecesLimit; // New: Maximum total pieces allowed
  final Function(List<RawMaterialMapping>) onMappingChanged;

  const RawMaterialsQuantitySelector({
    super.key,
    required this.orgId,
    this.selectedMappings,
    this.totalPiecesLimit,
    required this.onMappingChanged,
  });

  @override
  State<RawMaterialsQuantitySelector> createState() => _RawMaterialsQuantitySelectorState();
}

class _RawMaterialsQuantitySelectorState extends State<RawMaterialsQuantitySelector> {
  final GrnService _grnService = GrnService();
  final TextEditingController _searchController = TextEditingController();
  
  List<RawMaterial> _allMaterials = [];
  List<RawMaterial> _filteredMaterials = [];
  List<RawMaterialMapping> _selectedMappings = [];
  bool _isLoading = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedMappings = List.from(widget.selectedMappings ?? []);
    _loadRawMaterials();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRawMaterials() async {
    setState(() => _isLoading = true);
    
    try {
      final materials = await _grnService.getRawMaterials(orgId: widget.orgId);
      setState(() {
        _allMaterials = materials;
        _filteredMaterials = materials;
      });
    } catch (e) {
      debugPrint('Error loading raw materials: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterMaterials(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMaterials = _allMaterials;
      } else {
        _filteredMaterials = _allMaterials.where((material) {
          return material.itemName.toLowerCase().contains(query.toLowerCase()) ||
                 material.itemCode.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _addMaterial(RawMaterial material) {
    debugPrint('➕ RAW_MATERIALS: Adding material ${material.itemName}');
    
    // Check if already added
    final existingIndex = _selectedMappings.indexWhere((m) => m.materialId == material.id);
    if (existingIndex >= 0) {
      debugPrint('⚠️ RAW_MATERIALS: Material already added');
      _showError('${material.itemName} is already added');
      return;
    }

    // Determine appropriate consumption unit based on stock unit
    String consumptionUnit = material.uom;
    if (material.uom.toUpperCase() == 'KG') {
      consumptionUnit = 'GM'; // Default to grams for consumption when stock is in KG
    } else if (material.uom.toUpperCase() == 'L') {
      consumptionUnit = 'ML'; // Default to milliliters for consumption when stock is in liters
    }

    debugPrint('➕ RAW_MATERIALS: Stock unit: ${material.uom}, Consumption unit: $consumptionUnit');

    final newMapping = RawMaterialMapping(
      materialId: material.id,
      materialName: material.itemName,
      materialCode: material.itemCode,
      uom: consumptionUnit, // Use consumption unit, not stock unit
      quantity: 1, // Default quantity
      costPrice: material.costPrice,
      currentStock: material.currentStock,
    );

    setState(() {
      _selectedMappings.add(newMapping);
    });
    
    debugPrint('➕ RAW_MATERIALS: Added mapping: ${newMapping.toJson()}');
    debugPrint('➕ RAW_MATERIALS: Total mappings: ${_selectedMappings.length}');
    
    widget.onMappingChanged(_selectedMappings);
  }

  void _removeMaterial(String materialId) {
    setState(() {
      _selectedMappings.removeWhere((m) => m.materialId == materialId);
    });
    widget.onMappingChanged(_selectedMappings);
  }

  void _updateQuantity(String materialId, double quantity) {
    debugPrint('🔢 RAW_MATERIALS: Updating quantity for $materialId to $quantity');
    
    final totalQuantity = _selectedMappings.fold<double>(0, (sum, mapping) => 
        mapping.materialId == materialId ? sum : sum + mapping.quantity) + quantity;
    
    // Check if exceeds limit
    if (widget.totalPiecesLimit != null && totalQuantity > widget.totalPiecesLimit!) {
      debugPrint('⚠️ RAW_MATERIALS: Quantity exceeds limit');
      _showError('Total quantity (${totalQuantity.toStringAsFixed(0)}) exceeds limit of ${widget.totalPiecesLimit} pieces');
      return;
    }

    setState(() {
      final index = _selectedMappings.indexWhere((m) => m.materialId == materialId);
      if (index >= 0) {
        final oldMapping = _selectedMappings[index];
        _selectedMappings[index] = RawMaterialMapping(
          materialId: oldMapping.materialId,
          materialName: oldMapping.materialName,
          materialCode: oldMapping.materialCode,
          uom: oldMapping.uom,
          quantity: quantity,
          costPrice: oldMapping.costPrice,
          currentStock: oldMapping.currentStock,
        );
        debugPrint('🔢 RAW_MATERIALS: Updated mapping: ${_selectedMappings[index].toJson()}');
      }
    });
    widget.onMappingChanged(_selectedMappings);
  }

  void _updateUnit(String materialId, String newUnit) {
    debugPrint('📏 RAW_MATERIALS: Updating unit for $materialId to $newUnit');
    
    setState(() {
      final index = _selectedMappings.indexWhere((m) => m.materialId == materialId);
      if (index >= 0) {
        final oldMapping = _selectedMappings[index];
        _selectedMappings[index] = RawMaterialMapping(
          materialId: oldMapping.materialId,
          materialName: oldMapping.materialName,
          materialCode: oldMapping.materialCode,
          uom: newUnit, // Update the unit
          quantity: oldMapping.quantity,
          costPrice: oldMapping.costPrice,
          currentStock: oldMapping.currentStock,
        );
        debugPrint('📏 RAW_MATERIALS: Updated mapping: ${_selectedMappings[index].toJson()}');
      }
    });
    widget.onMappingChanged(_selectedMappings);
  }

  void _clearAll() {
    setState(() => _selectedMappings.clear());
    widget.onMappingChanged(_selectedMappings);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 8),
        _buildSelectedMappings(),
        if (_isExpanded) ...[
          const SizedBox(height: 12),
          _buildSearchField(),
          const SizedBox(height: 8),
          _buildMaterialsList(),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    final totalQuantity = _selectedMappings.fold<double>(0, (sum, mapping) => sum + mapping.quantity);
    final isOverLimit = widget.totalPiecesLimit != null && totalQuantity > widget.totalPiecesLimit!;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Raw Materials Recipe',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              if (_selectedMappings.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.restaurant, color: Colors.green[600], size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${_selectedMappings.length} ingredient(s) mapped',
                      style: TextStyle(
                        color: Colors.green[700], 
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.totalPiecesLimit != null && isOverLimit) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.error, color: Colors.red[600], size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Exceeds limit!',
                        style: TextStyle(color: Colors.red[700], fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_selectedMappings.isNotEmpty)
          TextButton(
            onPressed: _clearAll,
            child: Text(
              'Clear All',
              style: TextStyle(color: Colors.red[600], fontSize: 12),
            ),
          ),
        IconButton(
          icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
          onPressed: () => setState(() => _isExpanded = !_isExpanded),
          tooltip: _isExpanded ? 'Collapse' : 'Add Raw Materials',
        ),
      ],
    );
  }

  Widget _buildSelectedMappings() {
    if (_selectedMappings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[600], size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No raw materials mapped. Click to add recipe ingredients.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant, color: Colors.green[600], size: 16),
              const SizedBox(width: 8),
              Text(
                'Recipe: ${_selectedMappings.length} ingredient(s)',
                style: TextStyle(
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._selectedMappings.map((mapping) => _buildMappingRow(mapping)).toList(),
        ],
      ),
    );
  }

  Widget _buildMappingRow(RawMaterialMapping mapping) {
    // Get the original raw material to get stock unit
    final originalMaterial = _allMaterials.firstWhere(
      (m) => m.id == mapping.materialId, 
      orElse: () => RawMaterial(
        id: '', 
        itemCode: '', 
        itemName: '', 
        uom: 'PCS', 
        costPrice: 0, 
        currentStock: 0
      )
    );
    
    final stockUnit = originalMaterial.uom;
    List<String> compatibleUnits = _getCompatibleUnits(stockUnit);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mapping.materialName,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                ),
                Text(
                  '${mapping.materialCode} • Stock: ${mapping.currentStock > 0 ? mapping.currentStock.toStringAsFixed(0) : 'N/A'} $stockUnit',
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: mapping.quantity.toStringAsFixed(mapping.quantity == mapping.quantity.toInt() ? 0 : 1),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: const OutlineInputBorder(),
                      hintText: 'Qty',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    style: const TextStyle(fontSize: 12),
                    onChanged: (value) {
                      final quantity = double.tryParse(value) ?? 0;
                      if (quantity > 0) {
                        _updateQuantity(mapping.materialId, quantity);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: mapping.uom,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    style: TextStyle(color: Colors.grey[700], fontSize: 10),
                    items: compatibleUnits.map((unit) => DropdownMenuItem(
                      value: unit,
                      child: Text(unit, style: const TextStyle(fontSize: 10)),
                    )).toList(),
                    onChanged: (newUnit) {
                      if (newUnit != null) {
                        _updateUnit(mapping.materialId, newUnit);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Show consumption amount clearly
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Text(
              '${mapping.quantity.toStringAsFixed(mapping.quantity == mapping.quantity.toInt() ? 0 : 1)} ${mapping.uom}',
              style: TextStyle(
                color: Colors.blue[700],
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.red[600]),
            onPressed: () => _removeMaterial(mapping.materialId),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  List<String> _getCompatibleUnits(String stockUnit) {
    final stockUnitUpper = stockUnit.toUpperCase();
    
    // Use the unit conversion service to get compatible units
    if (UnitConversionService.areUnitsCompatible(stockUnitUpper, 'GM')) {
      return ['GM', 'KG', 'LB', 'OZ'];
    } else if (UnitConversionService.areUnitsCompatible(stockUnitUpper, 'ML')) {
      return ['ML', 'L', 'GAL', 'FL_OZ'];
    } else if (UnitConversionService.areUnitsCompatible(stockUnitUpper, 'PCS')) {
      return ['PCS', 'DOZ', 'GROSS'];
    } else if (UnitConversionService.areUnitsCompatible(stockUnitUpper, 'CM')) {
      return ['CM', 'M', 'MM', 'IN', 'FT'];
    }
    
    // Default to original unit if no match
    return [stockUnit];
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search raw materials...',
        prefixIcon: const Icon(Icons.search, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      onChanged: _filterMaterials,
    );
  }

  Widget _buildMaterialsList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_filteredMaterials.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No raw materials found',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _filteredMaterials.length,
        itemBuilder: (context, index) {
          final material = _filteredMaterials[index];
          final isAdded = _selectedMappings.any((m) => m.materialId == material.id);

          return ListTile(
            dense: true,
            leading: Icon(
              isAdded ? Icons.check_circle : Icons.add_circle_outline,
              color: isAdded ? Colors.green[600] : Colors.orange[600],
              size: 20,
            ),
            title: Text(
              material.itemName,
              style: TextStyle(
                fontSize: 13, 
                fontWeight: FontWeight.w500,
                color: isAdded ? Colors.grey[500] : null,
              ),
            ),
            subtitle: Text(
              '${material.itemCode} • Stock: ${material.currentStock > 0 ? material.currentStock.toStringAsFixed(0) : 'N/A'} ${material.uom}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            trailing: Text(
              '₹${material.costPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: isAdded ? null : () => _addMaterial(material),
          );
        },
      ),
    );
  }
}