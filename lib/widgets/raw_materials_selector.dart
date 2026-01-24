import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../services/grn_service.dart';

class RawMaterialsSelector extends StatefulWidget {
  final String orgId;
  final List<String>? selectedMaterialIds;
  final Function(List<String>) onSelectionChanged;

  const RawMaterialsSelector({
    super.key,
    required this.orgId,
    this.selectedMaterialIds,
    required this.onSelectionChanged,
  });

  @override
  State<RawMaterialsSelector> createState() => _RawMaterialsSelectorState();
}

class _RawMaterialsSelectorState extends State<RawMaterialsSelector> {
  final GrnService _grnService = GrnService();
  final TextEditingController _searchController = TextEditingController();
  
  List<RawMaterial> _allMaterials = [];
  List<RawMaterial> _filteredMaterials = [];
  List<String> _selectedIds = [];
  bool _isLoading = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.selectedMaterialIds ?? []);
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

  void _toggleSelection(String materialId) {
    setState(() {
      if (_selectedIds.contains(materialId)) {
        _selectedIds.remove(materialId);
      } else {
        _selectedIds.add(materialId);
      }
    });
    widget.onSelectionChanged(_selectedIds);
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
    widget.onSelectionChanged(_selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 8),
        _buildSelectedMaterials(),
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
    return Row(
      children: [
        Expanded(
          child: Text(
            'Raw Materials Mapping',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        if (_selectedIds.isNotEmpty)
          TextButton(
            onPressed: _clearSelection,
            child: Text(
              'Clear All',
              style: TextStyle(color: Colors.red[600], fontSize: 12),
            ),
          ),
        IconButton(
          icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
          onPressed: () => setState(() => _isExpanded = !_isExpanded),
          tooltip: _isExpanded ? 'Collapse' : 'Select Raw Materials',
        ),
      ],
    );
  }

  Widget _buildSelectedMaterials() {
    if (_selectedIds.isEmpty) {
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
            Text(
              'No raw materials mapped. Click to select.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<RawMaterial>>(
      future: _grnService.getRawMaterialsByIds(
        orgId: widget.orgId,
        materialIds: _selectedIds,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final materials = snapshot.data ?? [];
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
                  Icon(Icons.check_circle, color: Colors.green[600], size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${materials.length} raw material(s) mapped',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: materials.map((material) => _buildMaterialChip(material)).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaterialChip(RawMaterial material) {
    return Chip(
      label: Text(
        material.itemName,
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: Colors.orange[100],
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: () => _toggleSelection(material.id),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
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
          final isSelected = _selectedIds.contains(material.id);

          return ListTile(
            dense: true,
            leading: Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelection(material.id),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            title: Text(
              material.itemName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${material.itemCode} • ${material.currentStock.toStringAsFixed(0)} ${material.uom}',
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
            onTap: () => _toggleSelection(material.id),
          );
        },
      ),
    );
  }
}