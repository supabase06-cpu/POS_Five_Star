import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final PrinterService _printerService = PrinterService();
  List<Printer> _printers = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isTesting = false;
  String? _selectedPrinter;
  PrinterStatus? _currentStatus;

  @override
  void initState() {
    super.initState();
    _initializePrinters();
    
    // Set up periodic status refresh
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      await _refreshStatus();
    });
  }

  Future<void> _initializePrinters() async {
    setState(() => _isLoading = true);
    
    try {
      await _printerService.initialize();
      await _refreshPrinters();
      await _refreshStatus();
      _selectedPrinter = _printerService.defaultPrinterName;
    } catch (e) {
      _showErrorSnackBar('Failed to initialize printers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _printerService.getPrinterStatusAsync();
      if (mounted) {
        setState(() {
          _currentStatus = status;
        });
      }
    } catch (e) {
      print('Error refreshing printer status: $e');
    }
  }

  Future<void> _refreshPrinters() async {
    setState(() => _isRefreshing = true);
    
    try {
      final printers = await _printerService.refreshPrinterList();
      setState(() {
        _printers = printers;
      });
      
      // Also refresh the status after refreshing printers
      await _refreshStatus();
    } catch (e) {
      _showErrorSnackBar('Failed to refresh printers: $e');
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _setDefaultPrinter(String printerName) async {
    try {
      final success = await _printerService.setDefaultPrinter(printerName);
      if (success) {
        setState(() => _selectedPrinter = printerName);
        await _refreshStatus(); // Refresh status after setting default printer
        _showSuccessSnackBar('Default printer set to: $printerName');
      } else {
        _showErrorSnackBar('Failed to set default printer');
      }
    } catch (e) {
      _showErrorSnackBar('Error setting default printer: $e');
    }
  }

  Future<void> _testPrint() async {
    if (_selectedPrinter == null) {
      _showErrorSnackBar('Please select a default printer first');
      return;
    }

    setState(() => _isTesting = true);
    
    try {
      final success = await _printerService.testPrint();
      if (success) {
        _showSuccessSnackBar('Test print sent successfully!');
      } else {
        _showErrorSnackBar('Test print failed');
      }
    } catch (e) {
      _showErrorSnackBar('Test print error: $e');
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _testConnectivity() async {
    if (_selectedPrinter == null) {
      _showErrorSnackBar('Please select a default printer first');
      return;
    }

    setState(() => _isTesting = true);

    try {
      print('🧪 Starting connectivity test for $_selectedPrinter...');
      
      // First refresh the status
      await _printerService.refreshStatus();
      
      // Then test actual connectivity
      final isConnected = await _printerService.testPrinterConnectivity(_selectedPrinter!);
      
      if (isConnected) {
        _showSuccessSnackBar('✅ Printer connectivity test PASSED! Printer is online and ready.');
        // Force refresh the status after successful test
        await _refreshStatus();
      } else {
        _showErrorSnackBar('❌ Printer connectivity test FAILED! Check printer connection and power.');
      }
    } catch (e) {
      _showErrorSnackBar('Connectivity test error: $e');
    } finally {
      setState(() => _isTesting = false);
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getConnectionType(Printer printer) {
    final url = (printer.url ?? '').toLowerCase();
    final name = printer.name.toLowerCase();

    if (url.contains('bluetooth') || name.contains('bluetooth') || name.contains('bt')) {
      return 'Bluetooth';
    } else if (url.contains('usb') || url.contains('lpt') || name.contains('usb')) {
      return 'USB/Cable';
    } else if (url.contains('http') || url.contains('ipp')) {
      return 'Network';
    }
    return 'USB/Cable';
  }

  IconData _getConnectionIcon(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'bluetooth':
        return Icons.bluetooth;
      case 'network':
        return Icons.wifi;
      default:
        return Icons.usb;
    }
  }

  Color _getConnectionColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'bluetooth':
        return Colors.blue;
      case 'network':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
        backgroundColor: Colors.orange[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isRefreshing ? null : _refreshPrinters,
            icon: _isRefreshing 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh Printers',
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Status Card
          _buildStatusCard(),
          
          const SizedBox(height: 24),
          
          // Available Printers Section
          _buildAvailablePrintersSection(),
          
          const SizedBox(height: 24),
          
          // Test Print Section
          _buildTestPrintSection(),
          
          const SizedBox(height: 24),
          
          // Instructions Card
          _buildInstructionsCard(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    // Use async status if available, otherwise fall back to sync status
    final status = _currentStatus ?? _printerService.getPrinterStatus();
    final hasDefault = status.hasDefaultPrinter;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasDefault ? Icons.print : Icons.print_disabled,
                  color: hasDefault ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Printer Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Add refresh button
                IconButton(
                  onPressed: () async {
                    await _printerService.refreshStatus();
                    await _refreshStatus();
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Printers',
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (hasDefault) ...[
              _buildStatusRow('Selected Printer', status.defaultPrinterName ?? 'Unknown'),
              _buildStatusRow('Connection Type', 'USB'),
            ] else ...[
              const Text(
                'No printer selected',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
              ),
            ],
            
            _buildStatusRow('Available Printers', '${status.availablePrintersCount} found'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value, 
            style: TextStyle(
              color: valueColor ?? Colors.grey[600],
              fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailablePrintersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Printers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_printers.length} found',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_printers.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.print_disabled, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No printers found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Make sure your printer is connected and installed',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _printers.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final printer = _printers[index];
                  final connectionType = _getConnectionType(printer);
                  final isSelected = _selectedPrinter == printer.name;
                  
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getConnectionColor(connectionType).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getConnectionIcon(connectionType),
                        color: _getConnectionColor(connectionType),
                      ),
                    ),
                    title: Text(
                      printer.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connection: $connectionType'),
                        if (printer.url.isNotEmpty)
                          Text(
                            'URL: ${printer.url}',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'SELECTED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ElevatedButton(
                          onPressed: isSelected ? null : () => _setDefaultPrinter(printer.name),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected ? Colors.grey : Colors.orange[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          child: Text(isSelected ? 'Selected' : 'Select'),
                        ),
                      ],
                    ),
                    isThreeLine: printer.url.isNotEmpty,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestPrintSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Test Print',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Send a test receipt to verify your printer is working correctly.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedPrinter == null || _isTesting ? null : _testPrint,
                icon: _isTesting 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.print),
                label: Text(_isTesting ? 'Printing...' : 'Send Test Print'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Add connectivity test button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedPrinter == null || _isTesting ? null : _testConnectivity,
                icon: _isTesting 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.wifi_find),
                label: Text(_isTesting ? 'Testing...' : 'Test Connectivity'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            
            if (_selectedPrinter == null)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please select a default printer first',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text(
                  'Setup Instructions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            const Text(
              'To use your POS printer with this application:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            
            _buildInstructionStep('1', 'Connect your printer via USB cable or pair via Bluetooth'),
            _buildInstructionStep('2', 'Install the printer driver from Windows Settings > Printers & Scanners'),
            _buildInstructionStep('3', 'Ensure the printer appears in the "Available Printers" list above'),
            _buildInstructionStep('4', 'Select your printer and click "Select" to set it as default'),
            _buildInstructionStep('5', 'Use "Send Test Print" to verify the connection'),
            
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tip: Both USB and Bluetooth printers work the same way once installed in Windows.',
                      style: TextStyle(fontSize: 12),
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

  Widget _buildInstructionStep(String number, String instruction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.orange[600],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}