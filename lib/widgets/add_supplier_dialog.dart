import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/inward_model.dart';
import '../services/supplier_service.dart';

class AddSupplierDialog extends StatefulWidget {
  final String orgId;
  final String? storeId;
  final Supplier? editSupplier; // For editing existing supplier

  const AddSupplierDialog({
    super.key,
    required this.orgId,
    this.storeId,
    this.editSupplier,
  });

  @override
  State<AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends State<AddSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supplierCodeController = TextEditingController();
  final _supplierNameController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _gstNumberController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _creditLimitController = TextEditingController(text: '0');
  
  bool _isSaving = false;
  bool _isGeneratingCode = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.editSupplier != null) {
      _populateEditData();
    } else {
      _generateSupplierCode();
    }
  }

  void _populateEditData() {
    final supplier = widget.editSupplier!;
    _supplierCodeController.text = supplier.supplierCode;
    _supplierNameController.text = supplier.supplierName;
    _contactPersonController.text = supplier.contactPerson ?? '';
    _phoneController.text = supplier.phone ?? '';
    _emailController.text = supplier.email ?? '';
    _addressController.text = supplier.address ?? '';
    _cityController.text = supplier.city ?? '';
    _stateController.text = supplier.state ?? '';
    _postalCodeController.text = supplier.postalCode ?? '';
    _gstNumberController.text = supplier.gstNumber ?? '';
    _panNumberController.text = supplier.panNumber ?? '';
    _creditLimitController.text = supplier.creditLimit.toString();
  }

  @override
  void dispose() {
    _supplierCodeController.dispose();
    _supplierNameController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _gstNumberController.dispose();
    _panNumberController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _generateSupplierCode() async {
    setState(() => _isGeneratingCode = true);
    
    try {
      final supplierService = SupplierService();
      final supplierCode = await supplierService.generateSupplierCode(widget.orgId, widget.storeId);
      _supplierCodeController.text = supplierCode;
    } catch (e) {
      debugPrint('❌ Generate supplier code error: $e');
      // Fallback to simple format if generation fails
      final timestamp = DateTime.now().millisecondsSinceEpoch % 10000;
      _supplierCodeController.text = 'SUP-$timestamp';
    }
    
    setState(() => _isGeneratingCode = false);
  }

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final supplierService = SupplierService();
      
      // Check for duplicate supplier code only if creating new supplier
      if (widget.editSupplier == null) {
        final isDuplicate = await supplierService.checkDuplicateSupplierCode(
          widget.orgId,
          _supplierCodeController.text.trim(),
        );
        
        if (isDuplicate) {
          setState(() {
            _errorMessage = 'Supplier code "${_supplierCodeController.text.trim()}" already exists';
            _isSaving = false;
          });
          return;
        }
      }

      Supplier? supplier;
      if (widget.editSupplier != null) {
        // Update existing supplier
        supplier = await supplierService.updateSupplier(
          supplierId: widget.editSupplier!.id,
          supplierName: _supplierNameController.text.trim(),
          contactPerson: _contactPersonController.text.trim().isEmpty ? null : _contactPersonController.text.trim(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
          state: _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
          postalCode: _postalCodeController.text.trim().isEmpty ? null : _postalCodeController.text.trim(),
          gstNumber: _gstNumberController.text.trim().isEmpty ? null : _gstNumberController.text.trim(),
          panNumber: _panNumberController.text.trim().isEmpty ? null : _panNumberController.text.trim(),
          creditLimit: double.tryParse(_creditLimitController.text) ?? 0,
        );
      } else {
        // Create new supplier
        supplier = await supplierService.createSupplier(
          orgId: widget.orgId,
          supplierCode: _supplierCodeController.text.trim(),
          supplierName: _supplierNameController.text.trim(),
          contactPerson: _contactPersonController.text.trim().isEmpty ? null : _contactPersonController.text.trim(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
          state: _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
          postalCode: _postalCodeController.text.trim().isEmpty ? null : _postalCodeController.text.trim(),
          gstNumber: _gstNumberController.text.trim().isEmpty ? null : _gstNumberController.text.trim(),
          panNumber: _panNumberController.text.trim().isEmpty ? null : _panNumberController.text.trim(),
          creditLimit: double.tryParse(_creditLimitController.text) ?? 0,
        );
      }

      if (supplier != null) {
        Navigator.pop(context, supplier);
      } else {
        setState(() {
          _errorMessage = widget.editSupplier != null ? 'Failed to update supplier. Please try again.' : 'Failed to create supplier. Please try again.';
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isSaving = false;
      });
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
                color: Colors.green[600],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_business, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    widget.editSupplier != null ? 'Edit Supplier' : 'Add New Supplier',
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
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _supplierCodeController,
                              decoration: InputDecoration(
                                labelText: 'Supplier Code *',
                                hintText: 'Auto-generated',
                                prefixIcon: const Icon(Icons.tag),
                                suffixIcon: widget.editSupplier != null ? null : (_isGeneratingCode 
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.refresh, size: 20),
                                        onPressed: _generateSupplierCode,
                                        tooltip: 'Generate new code',
                                      )),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              readOnly: true,
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _supplierNameController,
                              decoration: InputDecoration(
                                labelText: 'Supplier Name *',
                                hintText: 'Enter supplier name',
                                prefixIcon: const Icon(Icons.business),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
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
                              controller: _contactPersonController,
                              decoration: InputDecoration(
                                labelText: 'Contact Person *',
                                hintText: 'Contact person name',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              decoration: InputDecoration(
                                labelText: 'Phone Number *',
                                hintText: 'Enter 10-digit phone',
                                prefixIcon: const Icon(Icons.phone),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                if (v.length != 10) return 'Must be exactly 10 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'Enter email address',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [LengthLimitingTextInputFormatter(25)],
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            if (!RegExp(r'^[^@]+@[^@]+\.(com|in)$').hasMatch(v.trim())) {
                              return 'Email must end with .com or .in';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      // Address Information
                      const Text('Address Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: 'Address',
                          hintText: 'Enter full address',
                          prefixIcon: const Icon(Icons.location_on),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cityController,
                              decoration: InputDecoration(
                                labelText: 'City',
                                hintText: 'Enter city',
                                prefixIcon: const Icon(Icons.location_city),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stateController,
                              decoration: InputDecoration(
                                labelText: 'State',
                                hintText: 'Enter state',
                                prefixIcon: const Icon(Icons.map),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _postalCodeController,
                              decoration: InputDecoration(
                                labelText: 'Postal Code',
                                hintText: 'Enter postal code',
                                prefixIcon: const Icon(Icons.local_post_office),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Business Information
                      const Text('Business Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _gstNumberController,
                              decoration: InputDecoration(
                                labelText: 'GST Number *',
                                hintText: 'Enter GST number',
                                prefixIcon: const Icon(Icons.receipt_long),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [LengthLimitingTextInputFormatter(15)],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                // GST format: 2 digits state code + 10 digits PAN + 1 digit entity + 1 digit Z + 1 check digit
                                if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(v.trim())) {
                                  return 'Invalid GST format';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _panNumberController,
                              decoration: InputDecoration(
                                labelText: 'PAN Number',
                                hintText: 'Enter PAN number',
                                prefixIcon: const Icon(Icons.credit_card),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [LengthLimitingTextInputFormatter(10)],
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  // PAN format: 5 letters + 4 digits + 1 letter
                                  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v.trim())) {
                                    return 'Invalid PAN format';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _creditLimitController,
                        decoration: InputDecoration(
                          labelText: 'Credit Limit',
                          hintText: 'Enter credit limit',
                          prefixText: '₹ ',
                          prefixIcon: const Icon(Icons.account_balance_wallet),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid amount' : null,
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
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSupplier,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              widget.editSupplier != null ? 'Update Supplier' : 'Save Supplier',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                    ),
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