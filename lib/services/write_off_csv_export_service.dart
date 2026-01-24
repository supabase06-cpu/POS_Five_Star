import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/simple_write_off_model.dart';
import '../services/simple_write_off_service.dart';

class WriteOffCsvExportService {
  final SimpleWriteOffService _writeOffService;

  WriteOffCsvExportService(this._writeOffService);

  /// Export write-off data to CSV for the given date range
  Future<String> exportWriteOffToCsv({
    required String storeId,
    required List<SimpleWriteOffHeader> writeOffs,
    required Function(String) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      if (writeOffs.isEmpty) {
        onError('No data to export');
        return '';
      }

      // Check if date range exceeds 6 months (for performance)
      if (writeOffs.isNotEmpty) {
        final firstDate = writeOffs.last.createdAt; // Assuming sorted by date
        final lastDate = writeOffs.first.createdAt;
        final daysDifference = lastDate.difference(firstDate).inDays;
        
        if (daysDifference > 180) {
          onError('Export is limited to 6 months of data. Please select a smaller date range.');
          return '';
        }
      }

      // Get detailed write-off data for export
      final detailedData = await _getDetailedWriteOffData(writeOffs);
      
      // Generate CSV content
      final csvContent = _generateCsvContent(detailedData);
      
      // Save file
      final filePath = await _saveCsvFile(csvContent, onSuccess, onError);
      
      return filePath;
    } catch (e) {
      onError('Failed to export data: $e');
      return '';
    }
  }

  /// Get detailed write-off data with all items expanded
  Future<List<Map<String, dynamic>>> _getDetailedWriteOffData(List<SimpleWriteOffHeader> writeOffs) async {
    List<Map<String, dynamic>> detailedData = [];
    
    for (final writeOff in writeOffs) {
      // Get detailed items for each write-off
      final items = await _writeOffService.getWriteOffItems(writeOff.id);
      
      for (final item in items) {
        detailedData.add({
          'write_off_number': writeOff.writeOffNumber,
          'write_off_date': _formatIndianDateTime(writeOff.createdAt), // Use proper Indian time format
          'write_off_reason': WriteOffReason.getDisplayName(writeOff.writeOffReason),
          'product_code': item.productCode,
          'product_name': item.productName,
          'quantity': item.quantity,
          'uom': item.uom,
          'unit_cost': item.unitCost,
          'total_cost': item.totalAmount,
          'requested_by': writeOff.requestedByName ?? 'Unknown User',
        });
      }
    }
    
    return detailedData;
  }

  /// Generate CSV content from detailed data
  String _generateCsvContent(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return '';
    
    // CSV Headers
    final headers = [
      'Write Off Number',
      'Write Off Date',
      'Reason',
      'Product Code',
      'Product Name',
      'Quantity',
      'UOM',
      'Unit Cost',
      'Total Cost',
      'Requested By',
    ];
    
    // Build CSV content
    final csvLines = <String>[];
    csvLines.add(headers.join(','));
    
    for (final row in data) {
      final values = [
        _escapeCsvValue(row['write_off_number']),
        _escapeCsvValue(row['write_off_date']),
        _escapeCsvValue(row['write_off_reason']),
        _escapeCsvValue(row['product_code']),
        _escapeCsvValue(row['product_name']),
        row['quantity'].toString(),
        _escapeCsvValue(row['uom']),
        row['unit_cost'].toStringAsFixed(2),
        row['total_cost'].toStringAsFixed(2),
        _escapeCsvValue(row['requested_by']),
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
      final defaultFileName = 'WriteOff_Export_${dateStr}_$timeStr.csv';

      // Let user choose save location
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Write-off Export',
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