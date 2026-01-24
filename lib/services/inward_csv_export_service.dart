import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/inward_model.dart';
import '../services/inward_service.dart';

class InwardCsvExportService {
  final InwardService _inwardService;

  InwardCsvExportService(this._inwardService);

  /// Export inward data to CSV for the given date range
  Future<String> exportInwardToCsv({
    required String storeId,
    required List<InwardHeader> inwards,
    required Function(String) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      print('🔄 Starting CSV export with ${inwards.length} inward records');
      
      if (inwards.isEmpty) {
        onError('No data to export');
        return '';
      }

      // Check if date range exceeds 6 months (for performance)
      if (inwards.isNotEmpty) {
        final firstDate = inwards.last.receivedDate; // Assuming sorted by date
        final lastDate = inwards.first.receivedDate;
        final daysDifference = lastDate.difference(firstDate).inDays;
        
        if (daysDifference > 180) {
          onError('Export is limited to 6 months of data. Please select a smaller date range.');
          return '';
        }
      }

      print('📊 Getting detailed inward data...');
      // Get detailed inward data for export
      final detailedData = await _getDetailedInwardData(inwards);
      print('✅ Got ${detailedData.length} detailed records');
      
      if (detailedData.isEmpty) {
        onError('No detailed data found to export');
        return '';
      }
      
      print('📝 Generating CSV content...');
      // Generate CSV content
      final csvContent = _generateCsvContent(detailedData);
      print('✅ CSV content generated (${csvContent.length} characters)');
      
      print('💾 Saving CSV file...');
      // Save file
      final filePath = await _saveCsvFile(csvContent, onSuccess, onError);
      print('✅ CSV export completed: $filePath');
      
      return filePath;
    } catch (e, stackTrace) {
      print('❌ CSV export error: $e');
      print('Stack trace: $stackTrace');
      onError('Failed to export data: $e');
      return '';
    }
  }

  /// Get detailed inward data with all items expanded
  Future<List<Map<String, dynamic>>> _getDetailedInwardData(List<InwardHeader> inwards) async {
    List<Map<String, dynamic>> detailedData = [];
    
    try {
      for (int i = 0; i < inwards.length; i++) {
        final inward = inwards[i];
        print('📦 Processing inward ${i + 1}/${inwards.length}: ${inward.grnNumber}');
        
        // Get detailed items for each inward
        final details = await _inwardService.getInwardDetails(inward.id);
        if (details != null) {
          print('  ✅ Got details with ${details.items.length} items');
          
          for (final item in details.items) {
            // Calculate combined GST
            final totalGstPercentage = item.cgstPercentage + item.sgstPercentage;
            final totalGstAmount = item.cgstAmount + item.sgstAmount;
            
            detailedData.add({
              'grn_number': details.grnNumber,
              'received_date': _formatIndianDateTime(details.createdAt ?? details.receivedDate),
              'supplier_name': details.supplierName ?? 'Unknown Supplier',
              'supplier_invoice_no': details.supplierInvoiceNo ?? '',
              'product_code': item.productCode ?? '',
              'product_name': item.productName ?? '',
              'batch_no': item.batchNo ?? '',
              'manufacturing_date': item.manufacturingDate != null ? _formatIndianDate(item.manufacturingDate!) : '',
              'expiry_date': item.expiryDate != null ? _formatIndianDate(item.expiryDate!) : '',
              'open_date': item.openDate != null ? _formatIndianDate(item.openDate!) : '',
              'quantity': item.quantity,
              'uom': item.uom ?? '',
              'unit_cost': item.unitCost,
              'discount_percentage': item.discountPercentage,
              'discount_amount': item.discountAmount,
              'taxable_amount': item.taxableAmount,
              'gst_percentage': totalGstPercentage,
              'gst_amount': totalGstAmount,
              'total_cost': item.totalCost,
              'line_number': item.lineNumber,
              'received_by': details.receivedByName ?? 'Unknown User',
            });
          }
        } else {
          print('  ❌ No details found for inward: ${inward.grnNumber}');
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error in _getDetailedInwardData: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
    
    return detailedData;
  }

  /// Generate CSV content from detailed data
  String _generateCsvContent(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return '';
    
    // CSV Headers - Complete inward details with combined GST
    final headers = [
      'GRN Number',
      'Received Date',
      'Supplier Name',
      'Supplier Invoice No',
      'Product Code',
      'Product Name',
      'Batch No',
      'Manufacturing Date',
      'Expiry Date',
      'Open Date',
      'Quantity',
      'UOM',
      'Unit Cost',
      'Discount %',
      'Discount Amount',
      'Taxable Amount',
      'GST %',
      'GST Amount',
      'Total Cost',
      'Line Number',
      'Received By',
    ];
    
    // Build CSV content
    final csvLines = <String>[];
    csvLines.add(headers.join(','));
    
    for (final row in data) {
      final values = [
        _escapeCsvValue(row['grn_number']),
        _escapeCsvValue(row['received_date']),
        _escapeCsvValue(row['supplier_name']),
        _escapeCsvValue(row['supplier_invoice_no']),
        _escapeCsvValue(row['product_code']),
        _escapeCsvValue(row['product_name']),
        _escapeCsvValue(row['batch_no']),
        _escapeCsvValue(row['manufacturing_date']),
        _escapeCsvValue(row['expiry_date']),
        _escapeCsvValue(row['open_date']),
        row['quantity'].toString(),
        _escapeCsvValue(row['uom']),
        row['unit_cost'].toStringAsFixed(2),
        row['discount_percentage'].toStringAsFixed(2),
        row['discount_amount'].toStringAsFixed(2),
        row['taxable_amount'].toStringAsFixed(2),
        row['gst_percentage'].toStringAsFixed(2),
        row['gst_amount'].toStringAsFixed(2),
        row['total_cost'].toStringAsFixed(2),
        row['line_number'].toString(),
        _escapeCsvValue(row['received_by']),
      ];
      csvLines.add(values.join(','));
    }
    
    return csvLines.join('\n');
  }

  /// Escape CSV values to handle commas, quotes, and newlines
  String _escapeCsvValue(dynamic value) {
    final str = value.toString();
    if (str.contains(',') || str.contains('"') || str.contains('\n')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  /// Save CSV file with user file picker or clipboard fallback
  Future<String> _saveCsvFile(
    String csvContent,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    try {
      // Generate filename with current date
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final defaultFileName = 'Inward_Export_${dateStr}_$timeStr.csv';

      // Let user choose save location
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Inward Export',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputFile != null) {
        // Ensure the file has .csv extension
        if (!outputFile.toLowerCase().endsWith('.csv')) {
          outputFile = '$outputFile.csv';
        }

        // Write CSV content to file
        final file = File(outputFile);
        await file.writeAsString(csvContent);
        
        onSuccess('CSV file saved successfully: ${file.path}');
        return file.path;
      } else {
        // User cancelled, copy to clipboard as fallback
        await Clipboard.setData(ClipboardData(text: csvContent));
        onSuccess('Export cancelled. CSV data copied to clipboard instead.');
        return 'clipboard';
      }
    } catch (e) {
      // Fallback to clipboard if file saving fails
      try {
        await Clipboard.setData(ClipboardData(text: csvContent));
        onSuccess('Could not save file. CSV data copied to clipboard instead.');
        return 'clipboard';
      } catch (clipboardError) {
        onError('Failed to save CSV file and copy to clipboard: $e');
        return '';
      }
    }
  }

  /// Format date for CSV (DD/MM/YYYY)
  String _formatDateForCsv(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Format date only in Indian format (DD/MM/YYYY)
  String _formatIndianDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Format date and time for CSV in Indian format (DD/MM/YYYY HH:MM)
  String _formatDateTimeForCsv(DateTime dateTime) {
    return '${_formatDateForCsv(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format date and time in proper Indian format (DD/MM/YYYY HH:MM AM/PM)
  String _formatIndianDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    
    // Convert to 12-hour format with AM/PM
    int hour = dateTime.hour;
    String period = 'AM';
    
    if (hour == 0) {
      hour = 12; // Midnight
    } else if (hour == 12) {
      period = 'PM'; // Noon
    } else if (hour > 12) {
      hour = hour - 12;
      period = 'PM';
    }
    
    final hourStr = hour.toString().padLeft(2, '0');
    final minuteStr = dateTime.minute.toString().padLeft(2, '0');
    
    return '$day/$month/$year $hourStr:$minuteStr $period';
  }
}