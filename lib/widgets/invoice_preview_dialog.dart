import 'package:flutter/material.dart';
import '../models/item_model.dart';

class InvoicePreviewDialog extends StatelessWidget {
  final List<CartItem> cartItems;
  final String customerName;
  final String customerPhone;
  final VoidCallback onConfirmPayment;

  const InvoicePreviewDialog({
    super.key,
    required this.cartItems,
    required this.customerName,
    required this.customerPhone,
    required this.onConfirmPayment,
  });

  // Tax calculations (same as billing screen)
  double get subtotalExcludingTax {
    return cartItems.fold(0, (sum, cartItem) => sum + cartItem.taxExclusivePrice);
  }

  double get totalTaxAmount {
    return cartItems.fold(0, (sum, cartItem) => sum + cartItem.taxAmount);
  }

  double get cgst => totalTaxAmount / 2;
  double get sgst => totalTaxAmount / 2;
  double get totalAmount => subtotalExcludingTax + totalTaxAmount;

  // Get detailed tax breakdown by tax rate
  List<Map<String, dynamic>> get taxBreakdown {
    final Map<double, Map<String, double>> breakdown = {};
    
    for (final cartItem in cartItems) {
      final taxRate = cartItem.item.taxRate ?? 0;
      if (taxRate > 0) {
        if (!breakdown.containsKey(taxRate)) {
          breakdown[taxRate] = {
            'taxableAmount': 0.0,
            'taxAmount': 0.0,
          };
        }
        breakdown[taxRate]!['taxableAmount'] = 
            (breakdown[taxRate]!['taxableAmount'] ?? 0) + cartItem.taxExclusivePrice;
        breakdown[taxRate]!['taxAmount'] = 
            (breakdown[taxRate]!['taxAmount'] ?? 0) + cartItem.taxAmount;
      }
    }
    
    // Convert to list and sort by tax rate
    final List<Map<String, dynamic>> result = [];
    final sortedRates = breakdown.keys.toList()..sort();
    
    for (final rate in sortedRates) {
      final data = breakdown[rate]!;
      final cgstRate = rate / 2;
      final sgstRate = rate / 2;
      final cgstAmount = data['taxAmount']! / 2;
      final sgstAmount = data['taxAmount']! / 2;
      
      result.add({
        'totalRate': rate,
        'cgstRate': cgstRate,
        'sgstRate': sgstRate,
        'cgstAmount': cgstAmount,
        'sgstAmount': sgstAmount,
        'totalTaxAmount': data['taxAmount']!,
      });
    }
    
    return result;
  }

  List<CartItem> get unmappedItems {
    return cartItems.where((item) => 
      item.item.rawMaterialMapping == null || 
      item.item.rawMaterialMapping!.isEmpty
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700, // Increased from 600
        constraints: const BoxConstraints(maxHeight: 850), // Increased from 700
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[600],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    'Invoice Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Info
                    _buildCustomerInfo(),
                    const SizedBox(height: 20),
                    
                    // Raw Material Warning (if any)
                    if (unmappedItems.isNotEmpty) ...[
                      _buildRawMaterialWarning(),
                      const SizedBox(height: 20),
                    ],
                    
                    // Items List
                    _buildItemsList(),
                    const SizedBox(height: 20),
                    
                    // Tax Breakdown
                    _buildTaxBreakdown(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            
            // Frozen Total Summary at Bottom
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: _buildTotalSummary(),
            ),
            
            // Frozen Action Buttons at Bottom
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onConfirmPayment();
                      },
                      icon: const Icon(Icons.payment),
                      label: const Text('Confirm Payment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildCustomerInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer Information',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text('Name: $customerName'),
          if (customerPhone.isNotEmpty) Text('Phone: $customerPhone'),
        ],
      ),
    );
  }

  Widget _buildRawMaterialWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text(
                'Raw Material Mapping Missing',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'The following ${unmappedItems.length} product(s) do not have raw material mapping configured:',
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          ...unmappedItems.map((item) => Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              '• ${item.item.itemName}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          )),
          const SizedBox(height: 8),
          Text(
            'Stock tracking may not be accurate for these items.',
            style: TextStyle(
              color: Colors.orange[700],
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Item', style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(child: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                Expanded(child: Text('Price', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
              ],
            ),
          ),
          // Items
          ...cartItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: index < cartItems.length - 1 
                    ? BorderSide(color: Colors.grey[200]!) 
                    : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(item.item.itemName),
                  ),
                  Expanded(
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '₹${item.item.sellingPrice.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '₹${item.totalPrice.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTaxBreakdown() {
    final breakdown = taxBreakdown;
    if (breakdown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tax Breakdown',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('CGST', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text('SGST', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                ),
                child: const Row(
                  children: [
                    Expanded(child: Text('%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                    Expanded(child: Text('Value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                    Expanded(child: Text('%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                    Expanded(child: Text('Value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                    Expanded(child: Text('%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                    Expanded(child: Text('Value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                  ],
                ),
              ),
              
              // Tax rate rows
              ...breakdown.map((tax) => Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text('${tax['cgstRate'].toStringAsFixed(1)}%', textAlign: TextAlign.center)),
                    Expanded(child: Text('₹${tax['cgstAmount'].toStringAsFixed(0)}', textAlign: TextAlign.center)),
                    Expanded(child: Text('${tax['sgstRate'].toStringAsFixed(1)}%', textAlign: TextAlign.center)),
                    Expanded(child: Text('₹${tax['sgstAmount'].toStringAsFixed(0)}', textAlign: TextAlign.center)),
                    Expanded(child: Text('${tax['totalRate'].toStringAsFixed(1)}%', textAlign: TextAlign.center)),
                    Expanded(child: Text('₹${tax['totalTaxAmount'].toStringAsFixed(0)}', textAlign: TextAlign.center)),
                  ],
                ),
              )),
              
              // Total row (if multiple tax rates)
              if (breakdown.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(child: Text('₹${cgst.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(child: Text('₹${sgst.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(child: Text('₹${totalTaxAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotalSummary() {
    return Column(
      children: [
        _buildSummaryRow('Subtotal (Tax Exclusive)', '₹${subtotalExcludingTax.toStringAsFixed(2)}'),
        const SizedBox(height: 8),
        _buildSummaryRow('Total Tax', '₹${totalTaxAmount.toStringAsFixed(2)}'),
        const Divider(thickness: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total Amount',
              style: TextStyle(
                fontSize: 20, // Increased font size
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '₹${totalAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 28, // Increased font size
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}