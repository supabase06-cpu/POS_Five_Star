import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'raw_usb_printer.dart';

class PrinterService {
  static const String _printerNameKey = 'selected_printer_name';
  
  // Singleton pattern
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  String? _selectedPrinterName;
  List<Printer> _availablePrinters = [];
  bool _isInitialized = false;

  // Simple stream for compatibility (no continuous monitoring)
  final StreamController<PrinterStatus> _statusController = StreamController<PrinterStatus>.broadcast();
  Stream<PrinterStatus> get statusStream => _statusController.stream;

  // Getters (keeping compatibility with old interface)
  String? get selectedPrinterName => _selectedPrinterName;
  String? get defaultPrinterName => _selectedPrinterName; // Alias for compatibility
  List<Printer> get availablePrinters => _availablePrinters;
  bool get hasSelectedPrinter => _selectedPrinterName != null;
  bool get hasDefaultPrinter => _selectedPrinterName != null; // Alias for compatibility
  bool get isInitialized => _isInitialized;

  /// Initialize the printer service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadSavedSettings();
      await refreshPrinterList();
      _isInitialized = true;
      
      print('✅ Printer service initialized');
      print('   Selected printer: ${_selectedPrinterName ?? "None"}');
      print('   Available printers: ${_availablePrinters.length}');
    } catch (e) {
      print('❌ Error initializing printer service: $e');
    }
  }

  /// Load saved printer settings
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPrinterName = prefs.getString(_printerNameKey);
  }

  /// Get list of available printers
  Future<List<Printer>> refreshPrinterList() async {
    try {
      _availablePrinters = await Printing.listPrinters();
      print('🖨️ Found ${_availablePrinters.length} printers');
      for (final printer in _availablePrinters) {
        print('   - ${printer.name}');
      }
      return _availablePrinters;
    } catch (e) {
      print('❌ Error listing printers: $e');
      _availablePrinters = [];
      return [];
    }
  }

  /// Set selected printer (compatibility methods)
  Future<bool> setSelectedPrinter(String printerName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_printerNameKey, printerName);
      _selectedPrinterName = printerName;
      
      print('✅ Selected printer set to: $printerName');
      _notifyStatusChange();
      return true;
    } catch (e) {
      print('❌ Error setting selected printer: $e');
      return false;
    }
  }

  Future<bool> setDefaultPrinter(String printerName) => setSelectedPrinter(printerName); // Alias

  /// Clear selected printer
  Future<void> clearSelectedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_printerNameKey);
    _selectedPrinterName = null;
    _notifyStatusChange();
  }

  /// Get printer device by name
  Printer? getPrinterByName(String printerName) {
    try {
      return _availablePrinters.firstWhere((printer) => printer.name == printerName);
    } catch (e) {
      return null;
    }
  }

  /// Print using direct USB connection (on-demand) - bypasses Windows spooler
  Future<bool> printDirectPDF(Uint8List pdfData) async {
    if (_selectedPrinterName == null) {
      throw Exception('No printer selected');
    }

    final printer = getPrinterByName(_selectedPrinterName!);
    if (printer == null) {
      throw Exception('Selected printer not found');
    }

    try {
      print('🔌 Attempting direct print to: ${printer.name}');
      
      // Use the regular printing method - it should work now with the simplified raw USB approach
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (format) async => pdfData,
      );

      print('✅ Direct print completed successfully');
      return true;
      
    } catch (e) {
      print('❌ Direct print failed: $e');
      
      // Only throw exception for actual connection issues
      if (e.toString().contains('printer') || 
          e.toString().contains('offline') || 
          e.toString().contains('connection') ||
          e.toString().contains('not found')) {
        throw Exception('Printer not connected. Please check USB connection and power.');
      }
      
      // For other errors, just rethrow
      rethrow;
    }
  }

  /// Test printer connection using direct method
  Future<bool> testConnection() async {
    if (_selectedPrinterName == null) {
      throw Exception('No printer selected');
    }

    final printer = getPrinterByName(_selectedPrinterName!);
    if (printer == null) {
      throw Exception('Selected printer not found');
    }

    try {
      print('🧪 Testing connection to: ${printer.name}');
      
      // Create a simple test PDF
      final testPdf = await _createTestPdf();
      
      // Try to print it
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (format) async => testPdf,
      );
      
      print('✅ Connection test successful');
      return true;
    } catch (e) {
      print('❌ Connection test failed: $e');
      throw Exception('Printer not connected. Please check USB connection and power.');
    }
  }

  /// Create a simple test PDF
  Future<Uint8List> _createTestPdf() async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => pw.Column(
          children: [
            pw.Text('PRINTER TEST', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Date: ${DateTime.now().toString().substring(0, 19)}'),
            pw.Text('Printer: $_selectedPrinterName'),
            pw.SizedBox(height: 10),
            pw.Text('Test successful!'),
          ],
        ),
      ),
    );
    
    return pdf.save();
  }

  /// Compatibility methods for existing code
  Future<bool> testPrint() => testConnection();
  Future<bool> testPrinterConnectivity(String printerName) => testConnection();
  Future<void> refreshStatus() async {
    await refreshPrinterList();
    _notifyStatusChange();
  }

  /// Simple status check - just checks if printer is in the list
  bool isPrinterAvailable() {
    return hasSelectedPrinter && getPrinterByName(_selectedPrinterName!) != null;
  }

  /// Get printer status (sync version)
  PrinterStatus getPrinterStatus() {
    return PrinterStatus(
      isInitialized: _isInitialized,
      hasDefaultPrinter: hasSelectedPrinter,
      defaultPrinterName: _selectedPrinterName,
      availablePrintersCount: _availablePrinters.length,
      isDefaultPrinterAvailable: isPrinterAvailable(),
      isPrinterReady: isPrinterAvailable(),
    );
  }

  /// Get printer status (async version for compatibility)
  Future<PrinterStatus> getPrinterStatusAsync() async {
    return getPrinterStatus();
  }

  /// Notify status change
  void _notifyStatusChange() {
    if (!_statusController.isClosed) {
      _statusController.add(getPrinterStatus());
    }
  }

  /// Dispose resources
  void dispose() {
    _statusController.close();
  }
}

/// Simple printer status class
class PrinterStatus {
  final bool isInitialized;
  final bool hasDefaultPrinter;
  final String? defaultPrinterName;
  final int availablePrintersCount;
  final bool isDefaultPrinterAvailable;
  final bool isPrinterReady;

  PrinterStatus({
    required this.isInitialized,
    required this.hasDefaultPrinter,
    this.defaultPrinterName,
    required this.availablePrintersCount,
    required this.isDefaultPrinterAvailable,
    required this.isPrinterReady,
  });

  // Compatibility getters
  bool get isInitializing => false; // No longer used
  String? get printerType => 'USB'; // Simple default

  @override
  String toString() {
    return 'PrinterStatus(isReady: $isPrinterReady, hasDefault: $hasDefaultPrinter, available: $isDefaultPrinterAvailable)';
  }
}