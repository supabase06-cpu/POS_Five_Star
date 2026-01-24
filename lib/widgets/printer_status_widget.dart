import 'dart:async';
import 'package:flutter/material.dart';
import '../services/printer_service.dart';
import '../services/invoice_printer_service.dart';
import '../screens/printer_settings_screen.dart';

class PrinterStatusWidget extends StatefulWidget {
  final VoidCallback? onPrinterReady;
  final bool showFullStatus;

  const PrinterStatusWidget({
    super.key,
    this.onPrinterReady,
    this.showFullStatus = false,
  });

  @override
  State<PrinterStatusWidget> createState() => _PrinterStatusWidgetState();
}

class _PrinterStatusWidgetState extends State<PrinterStatusWidget> {
  final PrinterService _printerService = PrinterService();
  
  PrinterStatus? _currentStatus;

  @override
  void initState() {
    super.initState();
    _initializePrinter();
  }

  Future<void> _initializePrinter() async {
    // Initialize printer service if not already done
    await _printerService.initialize();
    
    // Get initial status
    final status = _printerService.getPrinterStatus();
    setState(() {
      _currentStatus = status;
    });
  }

  void _openPrinterSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PrinterSettingsScreen()),
    ).then((_) async {
      // Refresh status when returning from settings
      if (mounted) {
        final status = _printerService.getPrinterStatus();
        setState(() {
          _currentStatus = status;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStatus == null) {
      return _buildLoadingWidget();
    }

    if (widget.showFullStatus) {
      return _buildFullStatusWidget(_currentStatus!);
    } else {
      return _buildCompactStatusWidget(_currentStatus!);
    }
  }

  Widget _buildLoadingWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Loading printer...', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCompactStatusWidget(PrinterStatus status) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (status.hasDefaultPrinter) {
      statusColor = Colors.blue;
      statusIcon = Icons.print;
      statusText = 'Ready';
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.print_disabled;
      statusText = 'Not Set';
    }

    return InkWell(
      onTap: _openPrinterSettings,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, color: statusColor, size: 16),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.settings, color: statusColor, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildFullStatusWidget(PrinterStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.hasDefaultPrinter ? Icons.print : Icons.print_disabled,
                  color: status.hasDefaultPrinter ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Printer Settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openPrinterSettings,
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Settings'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (!status.hasDefaultPrinter) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'No printer selected. Click Settings to choose your printer.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.print, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Printer selected',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Printer: ${status.defaultPrinterName}', style: const TextStyle(fontSize: 12)),
                    Text('Type: USB', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Simple printer status indicator for toolbar/header use
class PrinterStatusIndicator extends StatefulWidget {
  const PrinterStatusIndicator({super.key});

  @override
  State<PrinterStatusIndicator> createState() => _PrinterStatusIndicatorState();
}

class _PrinterStatusIndicatorState extends State<PrinterStatusIndicator> {
  final PrinterService _printerService = PrinterService();
  PrinterStatus? _currentStatus;

  @override
  void initState() {
    super.initState();
    _initializeStatus();
  }

  Future<void> _initializeStatus() async {
    // Initialize printer service if not already done
    await _printerService.initialize();
    
    // Get initial status
    if (mounted) {
      final status = _printerService.getPrinterStatus();
      setState(() {
        _currentStatus = status;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_currentStatus == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 4),
            Text(
              'LOADING',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final status = _currentStatus!;
    final hasSelected = status.hasDefaultPrinter;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasSelected ? Colors.blue.withOpacity(0.9) : Colors.grey.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSelected ? Icons.print : Icons.print_disabled,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            hasSelected ? 'PRINTER SET' : 'NO PRINTER',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}